FROM debian:bookworm

# Install dependencies
ENV DEBIAN_FRONTEND=noninteractive

RUN echo "\
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware \n\
deb-src http://deb.debian.org/debian bookworm main contrib non-free-firmware \n\
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware \n\
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware \n\
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware \n\
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware" \
    > /etc/apt/sources.list
RUN rm -rf /etc/apt/sources.list.d/*

# Debian build essentials and Debcraft essentials
# Unfortunately this is almost 500 MB but here is no way around it. Luckily due
# to caching all rebuilds and all later containers will build much faster.
RUN apt-get update -q && \
    apt-get install -q --yes --no-install-recommends \
    blhc \
    ccache \
    curl \
    devscripts \
    eatmydata \
    equivs \
    fakeroot \
    git \
    git-buildpackage \
    lintian \
    pristine-tar

RUN apt update
RUN apt build-dep -y rauc

COPY ./config.sh ./update-sources.sh ./
RUN ./update-sources.sh --rauc --psplash

RUN DEBIAN_FRONTEND=noninteractive mk-build-deps -r -i components/rauc/rauc/debian/control \
    -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends'

RUN DEBIAN_FRONTEND=noninteractive mk-build-deps -r -i components/rauc/rauc-hawkbit-updater/debian/control \
    -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends'

RUN DEBIAN_FRONTEND=noninteractive mk-build-deps -r -i components/psplash/debian/control \
    -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends'