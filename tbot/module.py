import xml.etree.ElementTree as ET
import config
import requests
from netmiko import ConnectHandler


def get_info_gpon(clientInfo):
    fsp = clientInfo[0][0][0].attrib["fsp"]
    olt = clientInfo[0][0][0].attrib["olt"]
    ontid = clientInfo[0][0][0].attrib["ontId"]
    sn = clientInfo[0][0][0].attrib["sn"]
    return fsp, olt, ontid, sn


def parse_ip_olt(olt):
    status = False
    ip = ""
    for char in olt:
        if char == "]":
            status = False
        if status:
            ip = ip + char
        if char == "[":
            status = True
    return ip


def commands_to_connect_sn(HuaweiConfig, SN):
    ssh = ConnectHandler(**HuaweiConfig)
    ssh.enable()
    ssh.send_command("undo smart")
    ssh.send_command("scroll")
    info = ssh.send_command("display ont info by-sn " + SN, read_timeout=1000)
    return info


def search_string(info, search_target):
    ResStr = ""
    i = 0
    SearchStatus = False
    for char in info:
        ResStr = ResStr + char
        if char == search_target[i]:
            if i == len(search_target) - 1:
                SearchStatus = True
                i = 0
                continue
            i = i + 1
        else:
            i = 0
        if (char == "\n") and (not SearchStatus):
            ResStr = ""
        elif (char == "\n") and (SearchStatus):
            return ResStr


def parse_string(info, search_target):
    result = search_string(info, search_target).split(":")
    result = result[1].replace("\n", "")
    result = result.replace(" ", "", 1)
    return result


def online_or_offline(info):
    result = parse_string(info, "Run state")
    if "online" in result:
        return "online", "-"
    else:
        return False


def parse_info_sn(olt, HuaweiConfig, SN):
    ip = parse_ip_olt(olt)
    HuaweiConfig["ip"] = ip
    info = commands_to_connect_sn(HuaweiConfig, SN)
    # ldc - last down cause
    run_state, ldc = online_or_offline(info)
    # online_duration - ONT online duration
    online_duration = parse_string(info, "ONT online duration")
    return run_state, ldc, online_duration


def commands_to_connect_fsp(HuaweiConfig, fs, p, ontid):
    ssh = ConnectHandler(**HuaweiConfig)
    ssh.enable()
    ssh.send_command("undo smart")
    ssh.send_command("scroll")
    ssh.send_command("config", expect_string="#")
    ssh.send_command("interface gpon " + fs, expect_string="#")
    res = ssh.send_command(
        "display ont optical-info " + p + " " + ontid, expect_string="#"
    )
    return res


def parse_fsp(fsp):
    res = fsp.split("/")
    fs = res[0] + "/" + res[1]
    p = res[2]
    return fs, p


def parse_info_fsp(olt, fsp, ontid, HuaweiConfig):
    ip = parse_ip_olt(olt)
    fs, p = parse_fsp(fsp)
    HuaweiConfig["ip"] = ip
    info = commands_to_connect_fsp(HuaweiConfig, fs, p, ontid)
    rx_power = parse_string(info, "Rx optical power(dBm)")
    tx_power = parse_string(info, "Tx optical power(dBm)")
    return rx_power, tx_power
