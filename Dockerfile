FROM elixir:1.14.3-otp-24-alpine as build

RUN \
  apk add --no-cache \
  build-base \
  git \
  openssl1.1-compat-dev \
  libsrtp-dev \
  ffmpeg-dev \
  fdk-aac-dev \
  opus-dev \
  curl

WORKDIR /app

ENV RUSTFLAGS="-C target-feature=-crt-static"
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse 
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

RUN mix local.hex --force && \
  mix local.rebar --force

ENV MIX_ENV=prod

# The order of the following commands is important.
# It ensures that:
# * any changes in the `lib` directory will only trigger
# jellyfish compilation
# * any changes in the `config` directory will
# trigger both jellyfish and deps compilation
# but not deps fetching
# * any changes in the `config/runtime.exs` won't trigger 
# anything
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY lib lib
RUN mix compile

COPY config/runtime.exs config/

RUN mix release

FROM alpine:3.17 AS app

RUN addgroup -S jellyfish && adduser -S jellyfish -G jellyfish

# We run the whole image as root, fix permissions in
# the docker-entrypoint.sh and then use gosu to step-down
# from the root.
# See redis docker image for the reference
# https://github.com/docker-library/redis/blob/master/7.0/Dockerfile#L6
ENV GOSU_VERSION 1.16
RUN set -eux; \
	\
	apk add --no-cache --virtual .gosu-deps \
		ca-certificates \
		dpkg \
		gnupg \
	; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
# verify the signature
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	command -v gpgconf && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
# clean up fetch dependencies
	apk del --no-network .gosu-deps; \
	\
	chmod +x /usr/local/bin/gosu; \
# verify that the binary works
	gosu --version; \
	gosu nobody true

RUN \
  apk add --no-cache \
  openssl1.1-compat \
  libsrtp \
  ffmpeg \
  fdk-aac \
  opus \
  curl

WORKDIR /app

# base path where jellyfish saves its artefacts
ENV OUTPUT_BASE_PATH=./jellyfish_output

# override default (127, 0, 0, 1) IP by 0.0.0.0 
# as docker doesn't allow for connections outside the
# container when we listen to 127.0.0.1
ENV JF_IP=0.0.0.0

RUN mkdir ${OUTPUT_BASE_PATH} && chown jellyfish:jellyfish ${OUTPUT_BASE_PATH}

COPY --from=build /app/_build/prod/rel/jellyfish ./

COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x docker-entrypoint.sh

ENV HOME=/app

HEALTHCHECK CMD curl --fail -H "authorization: Bearer ${SERVER_API_TOKEN}" http://localhost:${PORT}/room || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]

CMD ["bin/jellyfish", "start"]
