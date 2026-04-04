FROM eclipse-temurin:21-jdk

RUN apt-get update && apt-get install -y \
    wget \
    xvfb \
    x11vnc \
    fluxbox \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://portswigger-cdn.net/burp/releases/download?product=community&type=Jar" -O /opt/burpsuite.jar

EXPOSE 8080 5900

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
