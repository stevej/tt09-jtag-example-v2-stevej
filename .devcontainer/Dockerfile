ARG VARIANT=ubuntu-22.04
FROM mcr.microsoft.com/vscode/devcontainers/base:${VARIANT}

ENV DEBIAN_FRONTEND=noninteractive
ENV PDK_ROOT=/home/vscode/ttsetup/pdk
ENV PDK=sky130A

RUN apt update && apt-get install build-essential -y && apt install -y autoconf gperf make gcc g++ bison flex
RUN apt install -y python3 python3-pip python3-venv python3-tk python-is-python3 libcairo2 verilator libpng-dev libqhull-dev wget

# Clone tt-support-tools
RUN mkdir -p /ttsetup
RUN git clone -b tt09 https://github.com/TinyTapeout/tt-support-tools /ttsetup/tt-support-tools

# (stevej) Install bespoke iverilog
RUN wget https://github.com/htfab/iverilog/archive/refs/tags/13.0-git-d8c3c51.tar.gz
RUN tar zxf 13.0-git-d8c3c51.tar.gz && cd /iverilog-13.0-git-d8c3c51 && \
    sh autoconf.sh && ./configure && make && make install

#RUN wget https://github.com/htfab/iverilog/releases/download/13.0-git-d8c3c51/iverilog_13.0-git-d8c3c51a-1_amd64.deb
#RUN apt-get install -y -q --no-install-recommends ./iverilog_13.0-git-d8c3c51a-1_amd64.deb

COPY test/requirements.txt /ttsetup/test_requirements.txt
COPY .devcontainer/copy_tt_support_tools.sh /ttsetup

RUN pip3 install -r /ttsetup/test_requirements.txt -r /ttsetup/tt-support-tools/requirements.txt

# Install verible (for formatting)
RUN umask 022 && \
    curl -L https://github.com/chipsalliance/verible/releases/download/v0.0-3795-gf4d72375/verible-v0.0-3795-gf4d72375-linux-static-x86_64.tar.gz | \
    tar zxf - -C /usr/local --strip-components=1 && \
    chmod 755 /usr/local/bin

# Install openlane
RUN pip3 install openlane==2.1.5
