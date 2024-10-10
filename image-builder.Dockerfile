FROM ubuntu:latest

WORKDIR /deps
COPY config.sh .
COPY update-sources.sh .
RUN mkdir misc
COPY ./misc/* ./misc

RUN apt update
RUN ./update-sources.sh --install_ubuntu_dependencies

RUN rm -r /deps
RUN apt install -y wget htop nano
WORKDIR /meticulous