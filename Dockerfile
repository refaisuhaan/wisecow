FROM ubuntu:22.04

RUN apt-get update && apt-get install -y fortune-mod cowsay netcat-traditional

ENV PATH="/usr/games:${PATH}"

WORKDIR /app
COPY wisecow.sh /app/wisecow.sh

RUN chmod +x /app/wisecow.sh
RUN apt-get update && apt-get install -y netcat-openbsd cowsay fortune-mod

EXPOSE 4499

CMD ["/app/wisecow.sh"]