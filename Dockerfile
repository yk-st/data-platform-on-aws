FROM amazon/aws-cli:2.17.59

RUN curl -L -o /usr/local/bin/jq \
    https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64 \
 && chmod +x /usr/local/bin/jq


WORKDIR /app