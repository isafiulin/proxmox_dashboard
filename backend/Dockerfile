FROM dart:stable AS runtime

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /root/.ssh \
    && chmod 700 /root/.ssh

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY bin ./bin
COPY lib ./lib
RUN chmod 700 /app/bin/ssh_askpass.sh

EXPOSE 8080
CMD ["dart", "run", "bin/server.dart"]
