FROM nimlang/nim:2.2.4-ubuntu-regular

RUN apt-get update -yqq \
    && apt-get install -y --no-install-recommends \
               libsass-dev \
               sqlite3 \
               libpcre3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

# add /app as safe.directory
RUN git config --global --add safe.directory /app

# install dependencies
RUN nimble install -Y
