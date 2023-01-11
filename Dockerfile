# syntax=docker/dockerfile:1.4

ARG DISTRIB_CODENAME="jammy"

################################################################################
# Base Stage.
################################################################################
FROM ubuntu:${DISTRIB_CODENAME} AS base

ARG DEBIAN_FRONTEND="noninteractive"
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    set -o errexit -o xtrace; \

    apt-get --yes --quiet update; \
    apt-get --yes --quiet install --no-install-recommends \
      build-essential \
      libgmp10 \
      libmpfr6 \
      libmpc3

WORKDIR /root

# TODO: move this to seperate stage
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    set -o errexit -o xtrace; \

    apt-get --yes --quiet update; \
    apt-get --yes --quiet install --no-install-recommends \
      ca-certificates \
      curl \
      libgmp-dev \
    ; \

    curl --silent --show-error --location --output isl.tar.gz \
      https://libisl.sourceforge.io/isl-0.18.tar.gz; \
    tar xvf isl.tar.gz; \
    cd isl-*; \
    ./configure; \
    make; \
    make install


################################################################################
# Dev Stage.
################################################################################
FROM base AS dev

ARG DEBIAN_FRONTEND="noninteractive"
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    --mount=type=tmpfs,target=/tmp set -o errexit -o xtrace; \
    apt-get --yes --quiet update; \
    apt-get --yes --quiet install --no-install-recommends \
      file \
      flex \
      ftp \
      libgmp-dev \
      libmpfr-dev \
      libmpc-dev \
      netbase \
      texinfo \
      zip

# Prepare directories for the `nobody` user.
RUN set -o errexit -o xtrace; \
    mkdir --verbose /nonexistent /opt/build; \
    chown --verbose nobody:nogroup /nonexistent /opt/build

COPY --link --chown=65534:65534 gcc /opt/gcc

USER nobody

WORKDIR /opt/gcc

RUN --mount=type=tmpfs,target=/tmp set -o errexit -o xtrace; \
    # ecj.jar needs to be downloaded separately in the gcc source root dir.
    contrib/download_ecj

RUN --mount=type=tmpfs,target=/tmp set -o errexit -o xtrace; \
    # Prepare the ccache cache dir.
    mkdir /nonexistent/

    # Remove ustat references in `sanitizer_platform_limits_posix.cc` because
    # ustat was deprecated.
    sed -i '/ustat/d' \
      libsanitizer/sanitizer_common/sanitizer_platform_limits_posix.cc; \

COPY bin/* /usr/local/bin/

WORKDIR /opt/build

# Reduce verbosity of the compilation process.
ARG MAKEFLAGS="V=0 --silent"

# configure
RUN --mount=type=tmpfs,target=/tmp set -o errexit -o xtrace; \
    /opt/gcc/configure \
      --disable-multilib \
      --enable-languages=java \
      # cause build rules to be less verbose
      --enable-silent-rules


################################################################################
# Build Stage.
################################################################################
FROM dev AS build

RUN --mount=type=tmpfs,target=/tmp make bootstrap

#ARG r="/opt/build"
#ARG s="/opt/gcc"
#
#RUN echo stage3 > stage_final
#
#RUN --mount=type=cache,from=base,source=/tmp,target=/tmp make stage1-bubble
#
#RUN --mount=type=cache,from=base,source=/tmp,target=/tmp make stage2-bubble
#
#RUN --mount=type=cache,from=base,source=/tmp,target=/tmp make stage3-bubble
#
#RUN --mount=type=cache,from=base,source=/tmp,target=/tmp make all-host

USER root
RUN --mount=type=tmpfs,target=/tmp make install


################################################################################
# Final Stage.
################################################################################
FROM base

COPY --from=build /usr/local /usr/local

ENTRYPOINT [ "/usr/local/bin/gcj" ]
CMD        [ "--help" ]
