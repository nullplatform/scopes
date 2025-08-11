FROM alpine

# Install essential tools and Go
RUN apk add --no-cache curl ca-certificates bash openssl aws-cli gettext gomplate jq yq go

# Install Nullplatform tools
RUN curl https://cli.nullplatform.com/install.sh | sh
RUN curl https://cli.nullplatform.com/agent/install.sh | sh
RUN mkdir -p /root/.np

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Set up Go environment
ENV GOPATH=/go
ENV PATH=$PATH:/go/bin

# Copy files
ADD start.sh /app/start.sh
RUN chmod +x /app/start.sh
ADD .. /root/.np/services

# Set PATH
ENV PATH=$PATH:/root/.local/bin

ENTRYPOINT ["/app/start.sh"]
