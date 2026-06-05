FROM dart:stable AS runtime

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY bin ./bin
COPY lib ./lib

EXPOSE 8080
CMD ["dart", "run", "bin/server.dart"]
