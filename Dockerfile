FROM ubuntu:22.04 AS lint
RUN apt-get update && apt-get install -y --no-install-recommends shellcheck && rm -rf /var/lib/apt/lists/*
COPY script.sh /src/script.sh
RUN shellcheck /src/script.sh

FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends python3 && rm -rf /var/lib/apt/lists/*
WORKDIR /var/www
COPY --from=lint /src/script.sh /usr/local/bin/script.sh
RUN chmod +x /usr/local/bin/script.sh
EXPOSE 8080
# python3 работает как PID 1 и игнорирует SIGTERM; по SIGINT http.server завершается с кодом 0
STOPSIGNAL SIGINT
CMD ["/bin/bash", "-c", "/usr/local/bin/script.sh; exec python3 -m http.server 8080"]
