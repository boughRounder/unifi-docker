FROM golang:1.17-bullseye as permset
WORKDIR /src
RUN git clone https://github.com/jacobalberty/permset.git /src && \
    mkdir -p /out && \
    go build -ldflags "-X main.chownDir=/unifi" -o /out/permset

FROM openjdk:8-jre-slim-buster

RUN mkdir -p /usr/unifi \
     /usr/local/unifi/init.d \
     /usr/unifi/init.d \
     /usr/local/docker

COPY ./scripts/docker-entrypoint.sh /usr/local/bin/
COPY ./scripts/docker-healthcheck.sh /usr/local/bin/
COPY ./scripts/functions /usr/unifi/functions
COPY ./scripts/import_cert /usr/unifi/init.d/
COPY ./scripts/docker-build.sh /usr/local/bin/
COPY pre_build /usr/local/docker/pre_build

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && chmod +x /usr/unifi/init.d/import_cert \
 && chmod +x /usr/local/bin/docker-healthcheck.sh \
 && chmod -R +x /usr/local/docker/pre_build \
 && chmod +x /usr/local/bin/docker-build.sh

ENV UNIFI_VERSION=7.0.23
ENV MONGODB_VERSION=5.0
ENV UNIFI_GID=999
ENV UNIFI_UID=999
ENV UNIFI_URL=https://dl.ui.com/unifi/${UNIFI_VERSION}/unifi_sysvinit_all.deb
ENV CERTNAME=cert.pem
ENV CERT_PRIVATE_NAME=privkey.pem
ENV CERT_IS_CHAIN=false
ENV BIND_PRIV=true
ENV RUNAS_UID0=true
        
# Install dependencies
RUN set -ex \
 && mkdir -p /usr/share/man/man1/ \
 && groupadd -r unifi -g $UNIFI_GID \
 && useradd --no-log-init -r -u $UNIFI_UID -g $UNIFI_GID unifi \
#  && echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/${MONGODB_VERISON} main" | tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERISON}.list \
 && echo 'deb https://www.ui.com/downloads/unifi/debian stable ubiquiti' | tee /etc/apt/sources.list.d/100-ubnt-unifi.list \
 && apt-get -q=2 update \
 && apt-get -q=2 --no-install-recommends install \
    apt-transport-https \
    curl \
    dirmngr \
    gosu \
    gpg \
    gpg-agent \
    # mongodb-org \    
    procps \
    software-properties-common
 && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 06E85760C0A52C50 \    

# Install unifi
RUN curl -L -o ./unifi.deb "${UNIFI_URL}" \
 && apt -qy install ./unifi.deb \
 && rm -f ./unifi.deb \
 && chown -R unifi:unifi /usr/lib/unifi \
 && rm -rf /var/lib/apt/lists/*

ENV BASEDIR=/usr/lib/unifi
ENV DATADIR=/unifi/data
ENV LOGDIR=/unifi/log
ENV CERTDIR=/unifi/cert
ENV RUNDIR=/unifi/run
ENV ORUNDIR=/var/run/unifi
ENV ODATADIR=/var/lib/unifi
ENV OLOGDIR=/var/log/unifi

# Configure directories
RUN rm -rf ${ODATADIR} ${OLOGDIR} ${ORUNDIR} \
 && mkdir -p ${DATADIR} ${LOGDIR} ${RUNDIR} \
 && ln -s ${DATADIR} ${BASEDIR}/data \
 && ln -s ${RUNDIR} ${BASEDIR}/run \
 && ln -s ${LOGDIR} ${BASEDIR}/logs \
 && ln -s ${DATADIR} ${ODATADIR} \
 && ln -s ${LOGDIR} ${OLOGDIR} \
 && ln -s ${RUNDIR} ${ORUNDIR} \
 && mkdir -p /var/cert ${CERTDIR} \
 && ln -s ${CERTDIR} /var/cert/unifi

COPY --from=permset /out/permset /usr/local/bin/permset
# Apply any hotfixes that were included
COPY hotfixes /usr/local/unifi/hotfixes

RUN chown 0.0 /usr/local/bin/permset \
 && chmod +s /usr/local/bin/permset
 && mkdir -p /unifi \
 && chown unifi:unifi -R /unifi \
 && chmod +x /usr/local/unifi/hotfixes/* \
 && run-parts /usr/local/unifi/hotfixes

VOLUME ["/unifi", "${RUNDIR}"]

EXPOSE 6789/tcp 8080/tcp 8443/tcp 8880/tcp 8843/tcp 3478/udp 10001/udp

WORKDIR /unifi

HEALTHCHECK --start-period=5m CMD /usr/local/bin/docker-healthcheck.sh || exit 1

# execute controller using JSVC like original debian package does
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["unifi"]