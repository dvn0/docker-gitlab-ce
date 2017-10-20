FROM debian:stretch
MAINTAINER sameer@damagehead.com

COPY ./banner /tmp/
RUN cat /tmp/banner

ENV GITLAB_VERSION=10.0.2 \
    RUBY_VERSION=2.3 \
    GOLANG_VERSION=1.8.3 \
    GITLAB_SHELL_VERSION=5.9.0 \
    GITLAB_WORKHORSE_VERSION=3.0.0 \
    GITLAB_PAGES_VERSION=0.5.1 \
    GITALY_SERVER_VERSION=0.38.0 \
    GITLAB_USER="git" \
    GITLAB_HOME="/home/git" \
    GITLAB_LOG_DIR="/var/log/gitlab" \
    GITLAB_CACHE_DIR="/etc/docker-gitlab" \
    RAILS_ENV=production \
    NODE_ENV=production

ENV GITLAB_INSTALL_DIR="${GITLAB_HOME}/gitlab" \
    GITLAB_SHELL_INSTALL_DIR="${GITLAB_HOME}/gitlab-shell" \
    GITLAB_WORKHORSE_INSTALL_DIR="${GITLAB_HOME}/gitlab-workhorse" \
    GITLAB_PAGES_INSTALL_DIR="${GITLAB_HOME}/gitlab-pages" \
    GITLAB_GITALY_INSTALL_DIR="${GITLAB_HOME}/gitaly" \
    GITLAB_DATA_DIR="${GITLAB_HOME}/data" \
    GITLAB_BUILD_DIR="${GITLAB_CACHE_DIR}/build" \
    GITLAB_RUNTIME_DIR="${GITLAB_CACHE_DIR}/runtime" \
    GITLAB_CONF_DIRECTORY="/tmp/configs" \
    EXEC_AS_GIT="sudo -HEu ${GITLAB_USER}"

ENV GITLAB_CLONE_URL=https://gitlab.com/gitlab-org/gitlab-ce.git \
    GITLAB_SHELL_URL=https://gitlab.com/gitlab-org/gitlab-shell/repository/archive.tar.gz \
    GITLAB_WORKHORSE_URL=https://gitlab.com/gitlab-org/gitlab-workhorse.git \
    GITLAB_PAGES_URL=https://gitlab.com/gitlab-org/gitlab-pages/repository/archive.tar.gz \
    GITLAB_GITALY_URL=https://gitlab.com/gitlab-org/gitaly/repository/archive.tar.gz \
    GEM_CACHE_DIR="${GITLAB_BUILD_DIR}/cache"

ENV BUILD_DEPENDENCIES="gcc g++ make patch pkg-config cmake paxctl \
    libc6-dev ruby${RUBY_VERSION}-dev  \
    libpq-dev zlib1g-dev libyaml-dev libssl-dev \
    libgdbm-dev libreadline-dev libncurses5-dev libffi-dev \
    libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev \
    gettext"

RUN echo 'APT::Install-Recommends 0;' >> /etc/apt/apt.conf.d/01norecommends \
 && echo 'APT::Install-Suggests 0;' >> /etc/apt/apt.conf.d/01norecommends \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y curl vim.tiny wget sudo net-tools ca-certificates unzip apt-transport-https gnupg2 dirmngr \
 && rm -rf /var/lib/apt/lists/*

# apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv E1DD270288B4E6030699E45FA1715D88E1DF1F24 \
# && echo "deb http://ppa.launchpad.net/git-core/ppa/ubuntu trusty main" >> /etc/apt/sources.list \
# && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 80F70E11F0F0D5F10CB20E62F5DA5F09C3173AA6 \
# && echo "deb http://ppa.launchpad.net/brightbox/ruby-ng/ubuntu trusty main" >> /etc/apt/sources.list \
# && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 8B3981E7A6852F782CC4951600A6F0A3C300EE8C \
# && echo "deb http://ppa.launchpad.net/nginx/stable/ubuntu trusty main" >> /etc/apt/sources.list \
# && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
# && echo 'deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main' > /etc/apt/sources.list.d/pgdg.list \

RUN wget --quiet -O - https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - \
 && echo 'deb https://deb.nodesource.com/node_8.x trusty main' > /etc/apt/sources.list.d/nodesource.list \
 && wget --quiet -O - https://dl.yarnpkg.com/debian/pubkey.gpg  | apt-key add - \
 && echo 'deb https://dl.yarnpkg.com/debian/ stable main' > /etc/apt/sources.list.d/yarn.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake pkg-config supervisor logrotate locales curl \
      nginx openssh-server postgresql-client redis-tools \
      ruby${RUBY_VERSION} python2.7 python-docutils nodejs yarn gettext-base \
      libpq-dev zlib1g-dev libyaml-dev libssl-dev \
      libgdbm-dev libre2-dev libreadline-dev libcurl4-openssl-dev libncurses5-dev libffi-dev \
      libxml2-dev libxslt-dev libcurl3 libicu-dev gettext \
 && update-locale LANG=C.UTF-8 LC_MESSAGES=POSIX \
 && locale-gen en_US.UTF-8 \
 && DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales \
 && gem install --no-document bundler \
 && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
 && curl --remote-name --progress https://www.kernel.org/pub/software/scm/git/git-2.8.4.tar.gz \
 && echo '626e319f8a24fc0866167ea5f6bf3e2f38f69d6cb2e59e150f13709ca3ebf301  git-2.8.4.tar.gz' | shasum -a256 -c - && tar -xzf git-2.8.4.tar.gz \
 && cd git-2.8.4/ \
 && ./configure \
 && make prefix=/usr/local all \
 && make prefix=/usr/local install

RUN ln -s /usr/local/bin/git /usr/bin/git

RUN mkdir -p ${GITLAB_LOG_DIR}/supervisor

COPY assets/build/ ${GITLAB_BUILD_DIR}/
COPY ./assets/build/config /tmp/configs

# install build dependencies for gem installation
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y ${BUILD_DEPENDENCIES}

# https://en.wikibooks.org/wiki/Grsecurity/Application-specific_Settings#Node.js
RUN paxctl -Cm `which nodejs`

# remove the host keys generated during openssh-server installation
RUN rm -rf /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

# add ${GITLAB_USER} user
RUN adduser --disabled-login --gecos 'GitLab' ${GITLAB_USER} \
 && passwd -d ${GITLAB_USER}

# set PATH (fixes cron job PATH issues)
RUN echo "PATH=/usr/local/sbin:/usr/local/bin:\$PATH" >> ${GITLAB_HOME}/.profile

# configure git for ${GITLAB_USER}
RUN ${EXEC_AS_GIT} git config --global core.autocrlf input
RUN ${EXEC_AS_GIT} git config --global gc.auto 0
RUN ${EXEC_AS_GIT} git config --global repack.writeBitmaps true

# shallow clone gitlab-ce
RUN echo "Cloning gitlab-ce v.${GITLAB_VERSION}..."
RUN ${EXEC_AS_GIT} git clone -q -b v${GITLAB_VERSION} --depth 1 ${GITLAB_CLONE_URL} ${GITLAB_INSTALL_DIR}

# ENV GITLAB_SHELL_VERSION="${GITLAB_SHELL_VERSION:-$(cat ${GITLAB_INSTALL_DIR}/GITLAB_SHELL_VERSION)}" \
#     GITLAB_WORKHORSE_VERSION="${GITLAB_WORKHOUSE_VERSION:-$(cat ${GITLAB_INSTALL_DIR}/GITLAB_WORKHORSE_VERSION)}" \
#     GITLAB_PAGES_VERSION="${GITLAB_PAGES_VERSION:-$(cat ${GITLAB_INSTALL_DIR}/GITLAB_PAGES_VERSION)}"

#download golang
RUN echo "Downloading Go ${GOLANG_VERSION}..."
RUN wget -cnv https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz -P ${GITLAB_BUILD_DIR}/
RUN tar -xf ${GITLAB_BUILD_DIR}/go${GOLANG_VERSION}.linux-amd64.tar.gz -C /tmp/

# install gitlab-shell
RUN echo "Downloading gitlab-shell v.${GITLAB_SHELL_VERSION}..."
RUN mkdir -p ${GITLAB_SHELL_INSTALL_DIR}
RUN wget -cq ${GITLAB_SHELL_URL}?ref=v${GITLAB_SHELL_VERSION} -O ${GITLAB_BUILD_DIR}/gitlab-shell-${GITLAB_SHELL_VERSION}.tar.gz
RUN tar xf ${GITLAB_BUILD_DIR}/gitlab-shell-${GITLAB_SHELL_VERSION}.tar.gz --strip 1 -C ${GITLAB_SHELL_INSTALL_DIR}
RUN rm -rf ${GITLAB_BUILD_DIR}/gitlab-shell-${GITLAB_SHELL_VERSION}.tar.gz
RUN chown -R ${GITLAB_USER}: ${GITLAB_SHELL_INSTALL_DIR}

RUN cd ${GITLAB_SHELL_INSTALL_DIR}
RUN ${EXEC_AS_GIT} cp -a ${GITLAB_SHELL_INSTALL_DIR}/config.yml.example ${GITLAB_SHELL_INSTALL_DIR}/config.yml
RUN /bin/bash ${GITLAB_CONF_DIRECTORY}/compile_gitlab_shell.sh
# RUN ${EXEC_AS_GIT} ./bin/install

# remove unused repositories directory created by gitlab-shell install
RUN ${EXEC_AS_GIT} rm -rf ${GITLAB_HOME}/repositories

# download gitlab-workhorse
RUN echo "Cloning gitlab-workhorse v.${GITLAB_WORKHORSE_VERSION}..."
# RUN mkdir -p ${GITLAB_WORKHORSE_INSTALL_DIR}
RUN ${EXEC_AS_GIT} git clone -q -b v${GITLAB_WORKHORSE_VERSION} --depth 1 ${GITLAB_WORKHORSE_URL} ${GITLAB_WORKHORSE_INSTALL_DIR} \
 && chown -R ${GITLAB_USER}: ${GITLAB_WORKHORSE_INSTALL_DIR}

#install gitlab-workhorse
RUN cd ${GITLAB_WORKHORSE_INSTALL_DIR} \
 && PATH=/tmp/go/bin:$PATH GOROOT=/tmp/go make install

#download pages
RUN echo "Downloading gitlab-pages v.${GITLAB_PAGES_VERSION}..."
RUN mkdir -p ${GITLAB_PAGES_INSTALL_DIR}
RUN wget -cq ${GITLAB_PAGES_URL}?ref=v${GITLAB_PAGES_VERSION} -O ${GITLAB_BUILD_DIR}/gitlab-pages-${GITLAB_PAGES_VERSION}.tar.gz
RUN tar xf ${GITLAB_BUILD_DIR}/gitlab-pages-${GITLAB_PAGES_VERSION}.tar.gz --strip 1 -C ${GITLAB_PAGES_INSTALL_DIR}
RUN rm -rf ${GITLAB_BUILD_DIR}/gitlab-pages-${GITLAB_PAGES_VERSION}.tar.gz
RUN chown -R ${GITLAB_USER}: ${GITLAB_PAGES_INSTALL_DIR}

#install gitlab-pages
ENV GODIR="/tmp/go/src/gitlab.com/gitlab-org/gitlab-pages"
RUN /bin/bash -c 'cd ${GITLAB_PAGES_INSTALL_DIR} \
 && mkdir -p "$(dirname "$GODIR")" \
 && ln -sfv "$(pwd -P)" "$GODIR" \
 && cd $GODIR \
 && PATH=/tmp/go/bin:$PATH GOROOT=/tmp/go make gitlab-pages \
 && mv gitlab-pages /usr/local/bin/'

# download gitaly
RUN echo "Downloading gitaly v.${GITALY_SERVER_VERSION}..."
RUN mkdir -p ${GITLAB_GITALY_INSTALL_DIR}
RUN wget -cq ${GITLAB_GITALY_URL}?ref=v${GITALY_SERVER_VERSION} -O ${GITLAB_BUILD_DIR}/gitaly-${GITALY_SERVER_VERSION}.tar.gz
RUN tar xf ${GITLAB_BUILD_DIR}/gitaly-${GITALY_SERVER_VERSION}.tar.gz --strip 1 -C ${GITLAB_GITALY_INSTALL_DIR}
RUN rm -rf ${GITLAB_BUILD_DIR}/gitaly-${GITALY_SERVER_VERSION}.tar.gz
RUN chown -R ${GITLAB_USER}: ${GITLAB_GITALY_INSTALL_DIR}
# copy default config for gitaly
RUN ${EXEC_AS_GIT} cp ${GITLAB_GITALY_INSTALL_DIR}/config.toml.example ${GITLAB_GITALY_INSTALL_DIR}/config.toml

# install gitaly
RUN cd ${GITLAB_GITALY_INSTALL_DIR} \
 && PATH=/tmp/go/bin:$PATH GOROOT=/tmp/go make install && make clean

# remove go
RUN rm -rf ${GITLAB_BUILD_DIR}/go${GOLANG_VERSION}.linux-amd64.tar.gz /tmp/go

# remove HSTS config from the default headers, we configure it in nginx
RUN ${EXEC_AS_GIT} sed -i "/headers\['Strict-Transport-Security'\]/d" ${GITLAB_INSTALL_DIR}/app/controllers/application_controller.rb

# revert `rake gitlab:setup` changes from gitlabhq/gitlabhq@a54af831bae023770bf9b2633cc45ec0d5f5a66a
RUN ${EXEC_AS_GIT} sed -i 's/db:reset/db:setup/' ${GITLAB_INSTALL_DIR}/lib/tasks/gitlab/setup.rake

# RUN cd ${GITLAB_INSTALL_DIR}

# install gems, use local cache if available
RUN /bin/bash ${GITLAB_CONF_DIRECTORY}/install_gems.sh
RUN cd ${GITLAB_INSTALL_DIR} \
 && ${EXEC_AS_GIT} bundle install -j$(nproc) --deployment --without development test mysql aws kerberos

# make sure everything in ${GITLAB_HOME} is owned by ${GITLAB_USER} user
RUN chown -v -R ${GITLAB_USER}: ${GITLAB_HOME}

# gitlab.yml and database.yml are required for `assets:precompile`
RUN ${EXEC_AS_GIT} cp ${GITLAB_INSTALL_DIR}/config/resque.yml.example ${GITLAB_INSTALL_DIR}/config/resque.yml
RUN ${EXEC_AS_GIT} cp ${GITLAB_INSTALL_DIR}/config/gitlab.yml.example ${GITLAB_INSTALL_DIR}/config/gitlab.yml
RUN ${EXEC_AS_GIT} cp ${GITLAB_INSTALL_DIR}/config/database.yml.postgresql ${GITLAB_INSTALL_DIR}/config/database.yml
# RUN ${EXEC_AS_GIT} cp ${GITLAB_INSTALL_DIR}/config/database.yml.mysql ${GITLAB_INSTALL_DIR}/config/database.yml

# Installs nodejs packages required to compile webpack
RUN cd ${GITLAB_INSTALL_DIR} \
 && ${EXEC_AS_GIT} yarn install --production --pure-lockfile \
 && ${EXEC_AS_GIT} yarn add ajv@^4.0.0

RUN echo "Compiling assets. Please be patient, this could take a while..."
RUN cd ${GITLAB_INSTALL_DIR} \
 && ${EXEC_AS_GIT} bundle exec rake gitlab:assets:compile USE_DB=false SKIP_STORAGE_VALIDATION=true

# remove auto generated ${GITLAB_DATA_DIR}/config/secrets.yml
RUN rm -rf ${GITLAB_DATA_DIR}/config/secrets.yml

# remove gitlab shell and workhorse secrets
RUN rm -f ${GITLAB_INSTALL_DIR}/.gitlab_shell_secret ${GITLAB_INSTALL_DIR}/.gitlab_workhorse_secret

RUN ${EXEC_AS_GIT} mkdir -p ${GITLAB_INSTALL_DIR}/tmp/pids/ ${GITLAB_INSTALL_DIR}/tmp/sockets/
RUN chmod -R u+rwX ${GITLAB_INSTALL_DIR}/tmp

# symlink ${GITLAB_HOME}/.ssh -> ${GITLAB_LOG_DIR}/gitlab
RUN rm -rf ${GITLAB_HOME}/.ssh
RUN ${EXEC_AS_GIT} ln -sf ${GITLAB_DATA_DIR}/.ssh ${GITLAB_HOME}/.ssh

# symlink ${GITLAB_INSTALL_DIR}/log -> ${GITLAB_LOG_DIR}/gitlab
RUN rm -rf ${GITLAB_INSTALL_DIR}/log
RUN ln -sf ${GITLAB_LOG_DIR}/gitlab ${GITLAB_INSTALL_DIR}/log

# symlink ${GITLAB_INSTALL_DIR}/public/uploads -> ${GITLAB_DATA_DIR}/uploads
RUN rm -rf ${GITLAB_INSTALL_DIR}/public/uploads
RUN ${EXEC_AS_GIT} ln -sf ${GITLAB_DATA_DIR}/uploads ${GITLAB_INSTALL_DIR}/public/uploads

# symlink ${GITLAB_INSTALL_DIR}/.secret -> ${GITLAB_DATA_DIR}/.secret
RUN rm -rf ${GITLAB_INSTALL_DIR}/.secret
RUN ${EXEC_AS_GIT} ln -sf ${GITLAB_DATA_DIR}/.secret ${GITLAB_INSTALL_DIR}/.secret

# WORKAROUND for https://github.com/sameersbn/docker-gitlab/issues/509
RUN rm -rf ${GITLAB_INSTALL_DIR}/builds
RUN rm -rf ${GITLAB_INSTALL_DIR}/shared

# install gitlab bootscript, to silence gitlab:check warnings
RUN cp ${GITLAB_INSTALL_DIR}/lib/support/init.d/gitlab /etc/init.d/gitlab
RUN chmod +x /etc/init.d/gitlab

# disable default nginx configuration and enable gitlab's nginx configuration
RUN rm -rf /etc/nginx/sites-enabled/default

# configure sshd
RUN /bin/bash ${GITLAB_CONF_DIRECTORY}/sshd.sh

# move supervisord.log file to ${GITLAB_LOG_DIR}/supervisor/
RUN sed -i "s|^[#]*logfile=.*|logfile=${GITLAB_LOG_DIR}/supervisor/supervisord.log ;|" /etc/supervisor/supervisord.conf

# move nginx logs to ${GITLAB_LOG_DIR}/nginx
RUN /bin/bash ${GITLAB_CONF_DIRECTORY}/nginx.sh

# configure supervisord log rotation
RUN cat ${GITLAB_CONF_DIRECTORY}/logrotate-supervisord.conf > /etc/logrotate.d/supervisord

# configure gitlab log rotation
RUN cat ${GITLAB_CONF_DIRECTORY}/logrotate-gitlab.conf > /etc/logrotate.d/gitlab

# configure gitlab-shell log rotation
RUN cat ${GITLAB_CONF_DIRECTORY}/logrotate-gitlab-shell.conf > /etc/logrotate.d/gitlab-shell

# configure gitlab vhost log rotation
RUN cat ${GITLAB_CONF_DIRECTORY}/logrotate-gitlab-vhost.conf > /etc/logrotate.d/gitlab-nginx

# configure supervisord to start unicorn
RUN cat ${GITLAB_CONF_DIRECTORY}/supervisord-unicorn.conf > /etc/supervisor/conf.d/unicorn.conf

# configure supervisord to start sidekiq
RUN cat ${GITLAB_CONF_DIRECTORY}/supervisord-sidekiq.conf > /etc/supervisor/conf.d/sidekiq.conf

# configure supervisord to start gitlab-workhorse
RUN cat ${GITLAB_CONF_DIRECTORY}/supervisord-workhorse.conf > /etc/supervisor/conf.d/gitlab-workhorse.conf

# configure supervisord to start gitaly
RUN cat ${GITLAB_CONF_DIRECTORY}/supervisord-gitaly.conf > /etc/supervisor/conf.d/gitaly.conf

# configure supervisord to start mail_room
RUN cat ${GITLAB_CONF_DIRECTORY}/supervisord-mail_room.conf  > /etc/supervisor/conf.d/mail_room.conf

# configure supervisor to start sshd
RUN mkdir -p /var/run/sshd \
&& cat ${GITLAB_CONF_DIRECTORY}/supervisord-sshd.config  > /etc/supervisor/conf.d/sshd.conf

# configure supervisord to start nginx
RUN cat ${GITLAB_CONF_DIRECTORY}/supervisord-nginx.conf > /etc/supervisor/conf.d/nginx.conf

# configure supervisord to start crond
RUN cat ${GITLAB_CONF_DIRECTORY}/supervisord-crond.conf > /etc/supervisor/conf.d/cron.conf

# purge build dependencies and cleanup apt
RUN DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove ${BUILD_DEPENDENCIES}
RUN rm -rf /var/lib/apt/lists/*

COPY assets/runtime/ ${GITLAB_RUNTIME_DIR}/
COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 22/tcp 80/tcp 443/tcp

VOLUME ["${GITLAB_DATA_DIR}", "${GITLAB_LOG_DIR}"]
WORKDIR ${GITLAB_INSTALL_DIR}
ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["app:start"]
