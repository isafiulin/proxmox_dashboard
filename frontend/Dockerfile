FROM ghcr.io/cirruslabs/flutter:stable AS build

ARG FRONTEND_VERSION=development

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release --dart-define=APP_VERSION=$FRONTEND_VERSION

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
