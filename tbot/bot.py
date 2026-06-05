# -*- coding: utf-8 -*-
import telebot
import time
import config
import requests
import xml.etree.ElementTree as ET
import modules
import json
import logging
import sys
import traceback

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)

logger = logging.getLogger("neobot")

bot = telebot.TeleBot(config.token)

BGapi = config.BGapi
HuaweiConfig = config.HuaweiConfig
white_list_path = config.white_list_path
SmartData = config.SmartData
SmartHeaders = config.SmartHeaders
InfoOLT = config.InfoOLT


def get_billing_info(account_id):
    response = requests.get(BGapi.format(account_id), timeout=30)

    payload = response.json()
    if not isinstance(payload, dict):
        raise ValueError("Billing API returned an invalid JSON response")

    return response, payload


def format_money(value):
    if value is None:
        return "-"

    try:
        return "{:.2f}".format(float(value))
    except (TypeError, ValueError):
        return str(value)


def format_cost_items(items):
    if not items:
        return "-"

    return "\n".join(
        "- {}: {} сом".format(item.get("name", "-"), format_money(item.get("cost")))
        for item in items
    )


def format_client_state(state):
    states = {
        "ACTIVE": "Активен",
        "CLOSED": "Закрыт",
        "SUSPENDED": "Приостановлен",
        "DISABLED": "Отключен",
    }
    return states.get(state, state or "-")


def billing_error_message(payload):
    return payload.get("msg") or "Проверьте правильность введеных данных, ничего не найдено."


def log_message(message, command_name):
    logger.info(
        "%s received | chat_id=%s | chat_type=%s | user_id=%s | username=%s | text=%s",
        command_name,
        message.chat.id,
        message.chat.type,
        message.from_user.id if message.from_user else None,
        message.from_user.username if message.from_user else None,
        message.text,
    )


def log_done(command_name, message, started_at):
    logger.info(
        "%s done | chat_id=%s | duration=%.2fs",
        command_name,
        message.chat.id,
        time.time() - started_at,
    )


def log_error(command_name, message, error):
    logger.error(
        "%s error | chat_id=%s | error=%s",
        command_name,
        message.chat.id if message else None,
        error,
    )
    logger.error(traceback.format_exc())


def read_white_list():
    with open("./white_list.json", "r") as file:
        return json.load(file)


def write_white_list(data):
    with open(white_list_path, "w") as file:
        json.dump(data, file)


white_list = read_white_list()
logger.info("White list loaded | count=%s", len(white_list))


@bot.message_handler(commands=["start"])
def start_handler(message):
    started_at = time.time()
    log_message(message, "/start")

    try:
        bot.reply_to(message, str(message.chat.id))
        log_done("/start", message, started_at)
    except Exception as e:
        log_error("/start", message, e)


@bot.message_handler(commands=["info"])
def info_handler(message):
    started_at = time.time()
    log_message(message, "/info")

    try:
        if str(message.chat.id) not in white_list:
            logger.warning("/info denied | chat_id=%s", message.chat.id)
            bot.reply_to(message, "Я Вам ничего не скажу. Обратитесь к администратору. /report")
            return

        try:
            account_id = message.text.split(" ")[1]
        except IndexError:
            bot.reply_to(message, "Укажите лицевой счёт. Пример: /info 305000")
            return

        logger.info("/info request billing | account=%s | chat_id=%s", account_id, message.chat.id)

        response, payload = get_billing_info(account_id)
        logger.info("/info billing response | account=%s | http_status=%s | bytes=%s",
                    account_id, response.status_code, len(response.text))

        if payload.get("ok") and isinstance(payload.get("data"), dict):
            client = payload["data"]

            logger.info(
                "/info found | account=%s | status=%s | ip=%s",
                client.get("account"),
                client.get("state"),
                client.get("ip_address"),
            )

            lines = [
                "ФИО: {}".format(client.get("name", "-")),
                "Лицевой счёт: {}".format(client.get("account", "-")),
                "Статус абонента: {}".format(format_client_state(client.get("state"))),
                "Баланс: {} сом".format(format_money(client.get("balance"))),
                "Активен до: {}".format(client.get("period_end", "-")),
                "ТП:\n{}".format(format_cost_items(client.get("tariff"))),
            ]

            last_payment = client.get("last_payment")
            if isinstance(last_payment, dict):
                lines.append(
                    "Последний платёж: {} сом ({})".format(
                        format_money(last_payment.get("amount")),
                        last_payment.get("lm", "-"),
                    )
                )

            services = client.get("services")
            if services:
                lines.append("Дополнительные услуги:\n{}".format(format_cost_items(services)))

            if client.get("password") is not None:
                lines.append("Пароль для ЛК и ОТТ: {}".format(client["password"]))

            lines.append("IP Адрес: {}".format(client.get("ip_address", "-")))

            if client.get("cid") is not None:
                lines.append("CID: {}".format(client["cid"]))

            bot.reply_to(
                message,
                "\n".join(lines),
            )
        else:
            logger.warning(
                "/info billing error | account=%s | msg=%s | code=%s",
                account_id,
                payload.get("msg"),
                payload.get("code"),
            )
            bot.reply_to(message, billing_error_message(payload))

        log_done("/info", message, started_at)

    except Exception as e:
        log_error("/info", message, e)
        bot.reply_to(message, "Ошибка при выполнении команды /info")


@bot.message_handler(commands=["tv"])
def tv_handler(message):
    started_at = time.time()
    log_message(message, "/tv")

    try:
        if str(message.chat.id) not in white_list:
            logger.warning("/tv denied | chat_id=%s", message.chat.id)
            bot.reply_to(message, "Я Вам ничего не скажу. Обратитесь к администратору. /report")
            return

        try:
            sid = message.text.split(" ")[1]
        except IndexError:
            bot.reply_to(message, "Укажите SID. Пример: /tv 12345")
            return

        logger.info("/tv request | sid=%s | chat_id=%s", sid, message.chat.id)

        response = requests.post(
            "http://10.150.35.7:448/tvgw.ashx",
            data=SmartData.format(sid),
            headers=SmartHeaders,
            verify=False,
            timeout=30,
        ).text

        logger.info("/tv response | sid=%s | bytes=%s", sid, len(response))

        clientInfo = ET.fromstring(response)

        if clientInfo[0].attrib["STATUS"] == "2":
            data = clientInfo[0].attrib

            logger.info(
                "/tv found | sid=%s | status=%s | balance=%s",
                sid,
                data.get("ST"),
                data.get("BALANCE"),
            )

            bot.reply_to(
                message,
                "Статус абонента: {}\nФИО {}\nБаланс: {} сом\nТП: {}\nСтоимость ТП: {} сом".format(
                    data["ST"],
                    data["NAME"],
                    data["BALANCE"],
                    data["RATE"],
                    data["RATECOST"],
                ),
            )
        else:
            logger.warning("/tv not found | sid=%s", sid)
            bot.reply_to(message, "Проверьте правильность введеных данных, ничего не найдено.")

        log_done("/tv", message, started_at)

    except Exception as e:
        log_error("/tv", message, e)
        bot.reply_to(message, "Ошибка при выполнении команды /tv")


@bot.message_handler(commands=["gpon"])
def gpon_handler(message):
    started_at = time.time()
    log_message(message, "/gpon")

    try:
        if str(message.chat.id) != "-1001835206673":
            logger.warning("/gpon denied | chat_id=%s", message.chat.id)
            bot.reply_to(message, "Я вам ничего не скажу")
            return

        try:
            account_id = message.text.split(" ")[1]
        except IndexError:
            bot.reply_to(message, "Укажите лицевой счёт. Пример: /gpon 305000")
            return

        logger.info("/gpon request billing | account=%s | chat_id=%s", account_id, message.chat.id)

        response, payload = get_billing_info(account_id)
        logger.info("/gpon billing response | account=%s | http_status=%s | bytes=%s",
                    account_id, response.status_code, len(response.text))

        if not payload.get("ok") or not isinstance(payload.get("data"), dict):
            logger.warning(
                "/gpon billing error | account=%s | msg=%s | code=%s",
                account_id,
                payload.get("msg"),
                payload.get("code"),
            )
            bot.reply_to(message, billing_error_message(payload))
            return

        gpon = payload["data"].get("gpon")
        if not isinstance(gpon, dict):
            logger.warning("/gpon data missing | account=%s", account_id)
            bot.reply_to(message, "Для этого лицевого счёта данные GPON не найдены.")
            return

        FSP = gpon.get("fsp")
        OLT = gpon.get("olt")
        OntID = gpon.get("ont_id")
        SerialNum = gpon.get("sn")
        Model = gpon.get("model", "-")

        if not all([FSP, OLT, OntID, SerialNum]):
            logger.warning("/gpon data incomplete | account=%s | gpon=%s", account_id, gpon)
            bot.reply_to(message, "Для этого лицевого счёта данные GPON неполные.")
            return

        logger.info(
            "/gpon parsed | account=%s | olt=%s | fsp=%s | ont_id=%s | sn=%s | model=%s",
            account_id,
            OLT,
            FSP,
            OntID,
            SerialNum,
            Model,
        )

        modules.ParseBySerialNum(OLT, SerialNum, HuaweiConfig, InfoOLT)
        modules.ParseCatv(OLT, FSP, OntID, HuaweiConfig, InfoOLT)

        logger.info(
            "/gpon ont status | account=%s | olt=%s | status=%s | not_ont=%s",
            account_id,
            OLT,
            InfoOLT.get("OntStatus"),
            InfoOLT.get("NotOnt"),
        )

        if InfoOLT["OntStatus"] == "online":
            modules.ParseByFSP(OLT, FSP, OntID, HuaweiConfig, InfoOLT)

            logger.info(
                "/gpon online | account=%s | rx=%s | tx=%s | catv=%s",
                account_id,
                InfoOLT.get("RXPower"),
                InfoOLT.get("TXPower"),
                InfoOLT.get("CatvStatus"),
            )

            lines = [
                "OLT: {}".format(OLT),
                "FSP: {}".format(FSP),
                "ONT ID: {}".format(OntID),
                "Серийный номер: {}".format(SerialNum),
            ]
            if Model != "-":
                lines.append("Модель модема: {}".format(Model))
            lines.extend(
                [
                    "Статус модема: {}".format(InfoOLT["OntStatus"]),
                    "Продолжительность онлайн: {}".format(InfoOLT["OnlineDuration"]),
                    "Оптический сигнал приём: {}".format(InfoOLT["RXPower"]),
                    "Оптический сигнал отдача: {}".format(InfoOLT["TXPower"]),
                    "Статус CATV: {}".format(InfoOLT["CatvStatus"]),
                ]
            )
            bot.reply_to(message, "\n".join(lines))

        elif InfoOLT["OntStatus"] == "offline":
            logger.info(
                "/gpon offline | account=%s | last_cause=%s",
                account_id,
                InfoOLT.get("LastCause"),
            )

            lines = [
                "OLT: {}".format(OLT),
                "FSP: {}".format(FSP),
                "ONT ID: {}".format(OntID),
                "Серийный номер: {}".format(SerialNum),
            ]
            if Model != "-":
                lines.append("Модель модема: {}".format(Model))
            lines.extend(
                [
                    "Статус модема: {}".format(InfoOLT["OntStatus"]),
                    "Причина отключения: {}".format(InfoOLT["LastCause"]),
                ]
            )
            bot.reply_to(message, "\n".join(lines))

        elif InfoOLT["NotOnt"]:
            logger.warning("/gpon not ont | account=%s | sn=%s", account_id, SerialNum)
            bot.reply_to(message, "На OLT нет модемов с таким серийным номером. Обратитесь к команде /info")

        log_done("/gpon", message, started_at)

    except Exception as e:
        log_error("/gpon", message, e)
        bot.reply_to(message, "Ошибка при выполнении команды /gpon")


@bot.message_handler(commands=["add_chat"])
def add_chat_handler(message):
    started_at = time.time()
    log_message(message, "/add_chat")

    try:
        allowed_chat_ids = ["400629112", "212582449"]

        if str(message.chat.id) not in allowed_chat_ids:
            logger.warning("/add_chat denied | chat_id=%s", message.chat.id)
            return

        try:
            new_gid = message.text.split(" ")[1]
        except IndexError:
            bot.reply_to(message, "Укажите chat_id. Пример: /add_chat -100123456789")
            return

        if new_gid not in white_list:
            white_list.append(new_gid)
            write_white_list(white_list)

        logger.info("/add_chat added | new_chat_id=%s | by_chat_id=%s", new_gid, message.chat.id)

        bot.reply_to(message, "Добавлено.")
        log_done("/add_chat", message, started_at)

    except Exception as e:
        log_error("/add_chat", message, e)
        bot.reply_to(message, "Ошибка при выполнении команды /add_chat")


@bot.message_handler(commands=["onuinfo"])
def onuinfo_handler(message):
    started_at = time.time()
    log_message(message, "/onuinfo")

    try:
        split_values = message.text.split(":")
        olt_ip = split_values[0].split(" ")[1]
        sn_arr = split_values[1].split(",")

        logger.info(
            "/onuinfo request | chat_id=%s | olt_ip=%s | sn_count=%s",
            message.chat.id,
            olt_ip,
            len(sn_arr),
        )

        i = 0

        for item in sn_arr:
            sn = item.strip()

            logger.info("/onuinfo parse sn | olt_ip=%s | sn=%s", olt_ip, sn)

            modules.ParseBySerialNum2(olt_ip, sn, HuaweiConfig, InfoOLT)

            logger.info(
                "/onuinfo result | olt_ip=%s | sn=%s | status=%s | fsp=%s",
                olt_ip,
                sn,
                InfoOLT.get("OntStatus"),
                InfoOLT.get("fsp"),
            )

            bot.reply_to(
                message,
                "OLT: {}\nСтатус модема: {}\nПродолжительность онлайн: {}\nСерийный номер: {}\nFSP: {}".format(
                    olt_ip,
                    InfoOLT["OntStatus"],
                    InfoOLT["OnlineDuration"],
                    sn,
                    InfoOLT["fsp"],
                ),
            )

            i += 1

            if i >= 9:
                logger.info("/onuinfo sleep 30s after 9 requests")
                time.sleep(30)
                i = 0

        log_done("/onuinfo", message, started_at)

    except Exception as e:
        log_error("/onuinfo", message, e)
        bot.reply_to(message, "Формат: /onuinfo OLT_IP: SN1,SN2,SN3")


@bot.message_handler(func=lambda message: True)
def unknown_handler(message):
    logger.info(
        "unknown message | chat_id=%s | chat_type=%s | user_id=%s | username=%s | text=%s",
        message.chat.id,
        message.chat.type,
        message.from_user.id if message.from_user else None,
        message.from_user.username if message.from_user else None,
        message.text,
    )


if __name__ == "__main__":
    logger.info("Bot starting in polling mode")
    logger.info("Removing webhook...")

    try:
        bot.remove_webhook()
        time.sleep(1)
        logger.info("Webhook removed")
    except Exception as e:
        logger.error("Failed to remove webhook: %s", e)

    logger.info("Starting infinity polling...")

    bot.infinity_polling(
        timeout=20,
        long_polling_timeout=20,
        skip_pending=False,
    )
