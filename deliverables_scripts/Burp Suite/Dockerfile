FROM eclipse-temurin:21-jdk

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    fluxbox \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://portswigger-cdn.net/burp/releases/download?product=community&type=Jar" -O /opt/burpsuite.jar

EXPOSE 8080 5900 6080

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY scan_target.sh /scan_target.sh
RUN chmod +x /scan_target.sh

COPY index.html /usr/share/novnc/index.html

ENTRYPOINT ["/entrypoint.sh"]
