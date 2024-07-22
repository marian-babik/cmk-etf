FROM almalinux/9-base:latest

ARG check_mk_version="2.3.0p7"
ARG check_mk_package="check-mk-raw-${check_mk_version}-el9-38.x86_64.rpm"

LABEL description="ETF base image"
LABEL version="${check_mk_version}"

ARG check_mk_site="etf"

LABEL \
    org.opencontainers.image.title="ETF" \
    org.opencontainers.image.version="${check_mk_version}" \
    org.opencontainers.image.description="WLCG Experiments Test Framework (ETF)" \
    org.opencontainers.image.vendor="CERN" \
    org.opencontainers.image.source="https://gitlab.cern.ch/etf" \
    org.opencontainers.image.url="https://etf.cern.ch/docs/latest"

ENV CHECK_MK_SITE=${check_mk_site:-etf}
ENV CHECK_MK_VERSION=${check_mk_version}
ENV CMK_SITE_ID=${check_mk_site}

COPY ./config/etf9-stable.repo /etc/yum.repos.d/etf9-stable.repo

RUN yum -y install epel-release
RUN yum -y update

# Utils
RUN yum -y install vim-enhanced yum-utils nmap-ncat wget sendmail emacs

# ETF
RUN yum -y install python3-nap ncgx python3-vofeed-api
RUN yum -y install nagios-stream

# Check_MK
ADD https://download.checkmk.com/checkmk/$check_mk_version/$check_mk_package /tmp/$check_mk_package
RUN yum -y localinstall /tmp/$check_mk_package
RUN yum -y localinstall /opt/omd/versions/default/share/check_mk/agents/check-mk-agent-*.noarch.rpm

RUN omd create --no-tmpfs "$CMK_SITE_ID"
RUN omd config $check_mk_site set CORE nagios
RUN omd config $check_mk_site set LIVESTATUS_TCP on
RUN omd config $check_mk_site set LIVESTATUS_TCP_TLS off
RUN omd config $check_mk_site set NAGIOS_THEME exfoliation
RUN omd config $check_mk_site set MULTISITE_AUTHORISATION off
RUN omd config $check_mk_site set MULTISITE_COOKIE_AUTH off

# ETF auth
RUN mkdir -p /omd/sites/etf/var/check_mk/web/$check_mk_site \
    && chown -R $check_mk_site.$check_mk_site /omd/sites/etf/var/check_mk/web/$check_mk_site

# Link to standard nagios pipe
RUN mkdir -p /var/nagios/rw && ln -s /omd/sites/$check_mk_site/tmp/run/nagios.cmd /var/nagios/rw/nagios.cmd

# pnp4nagios tuning
RUN sed -i  "s/TRUE/FALSE/" /opt/omd/sites/$check_mk_site/etc/pnp4nagios/config.php
RUN sed -e "s|RRD_HEARTBEAT = 8460|RRD_HEARTBEAT = 25200|g" \
        -i /opt/omd/sites/$check_mk_site/etc/pnp4nagios/process_perfdata.cfg

# python env
RUN echo 'export PYTHONPATH=/usr/lib/python2.7/site-packages/:/usr/lib64/python2.7/site-packages' \
    >> /opt/omd/sites/$check_mk_site/.profile
    
# httpd ssl auth config
RUN rm -f /etc/httpd/conf.d/zzz_omd.conf
COPY ./config/ssl.conf /etc/httpd/conf.d/ssl.conf
COPY ./config/auth.conf /opt/omd/sites/$check_mk_site/etc/apache/conf.d/auth.conf
RUN echo "auth_by_http_header = 'X-Remote-User'" >> /omd/sites/$check_mk_site/etc/check_mk/multisite.mk

# disable welcome page
COPY .//config/welcome.conf /etc/httpd/conf.d/welcome.conf

# httpd logs to stdout/err
RUN sed -i 's|ErrorLog "logs/error_log"|ErrorLog /dev/stderr|g' /etc/httpd/conf/httpd.conf
RUN sed -i 's|CustomLog "logs/access_log" combined|CustomLog /dev/stdout combined|g' /etc/httpd/conf/httpd.conf

# httpd logs to stdout/err
RUN sed -i 's|ErrorLog "logs/error_log"|ErrorLog /dev/stderr|g' /etc/httpd/conf/httpd.conf
RUN sed -i 's|CustomLog "logs/access_log" combined|CustomLog /dev/stdout combined|g' /etc/httpd/conf/httpd.conf

# ETF config
RUN chown -R $check_mk_site.$check_mk_site /etc/ncgx
RUN chown -R $check_mk_site.$check_mk_site /var/cache/ncgx
RUN mkdir /var/cache/nap && chown -R $check_mk_site.$check_mk_site /var/cache/nap
COPY ./config/nagios.cfg /omd/sites/$check_mk_site/etc/nagios/nagios.cfg
COPY ./config/ncgx.cron /opt/omd/sites/$check_mk_site/etc/cron.d/ncgx
COPY ./config/etf.cron /etc/cron.d/etf_cleanup

HEALTHCHECK --interval=1m --timeout=5s \
    CMD omd status || exit 1

EXPOSE 443 6557 5000
