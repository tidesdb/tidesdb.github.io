FROM mariadb:11.4

# The compression backends are optional in the engine, but this build of the package was compiled
# with zstd, lz4 and snappy linked and declares none of them as dependencies. The base image
# already carries zstd and lz4 through mariadb-server, so only snappy has to be added here for the
# plugin to load. Drop libsnappy1v5 once the package declares its own runtime dependencies.
RUN set -eux; \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  mariadb-plugin-tidesdb libsnappy1v5; \
  rm -rf /var/lib/apt/lists/*

RUN printf '[mariadbd]\nplugin-maturity=beta\n' > /etc/mysql/mariadb.conf.d/zz-tidesdb.cnf

RUN mkdir -p /var/lib/tidesdb_data && chown mysql:mysql /var/lib/tidesdb_data

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306
CMD ["mariadbd"]
