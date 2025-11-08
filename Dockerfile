FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y sudo ca-certificates software-properties-common && \
    apt-add-repository -y ppa:landscape/self-hosted-24.04 && apt install -y landscape-server-quickstart

# Allow services to start at runtime if scripts expect it
RUN rm -f /usr/sbin/policy-rc.d
# Copy our entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh
RUN rm -rf /var/lib/apt/lists/*
EXPOSE 6554 443 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]