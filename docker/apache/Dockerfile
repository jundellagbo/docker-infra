FROM httpd:2.4-alpine

# Install required modules
RUN apk add --no-cache apache2-proxy apache2-ssl

# Enable required modules
RUN sed -i \
    -e 's/#LoadModule proxy_module/LoadModule proxy_module/' \
    -e 's/#LoadModule proxy_fcgi_module/LoadModule proxy_fcgi_module/' \
    -e 's/#LoadModule rewrite_module/LoadModule rewrite_module/' \
    -e 's/#LoadModule ssl_module/LoadModule ssl_module/' \
    -e 's/#LoadModule socache_shmcb_module/LoadModule socache_shmcb_module/' \
    /usr/local/apache2/conf/httpd.conf

# Enable vhosts include
RUN echo "IncludeOptional /etc/apache2/sites-enabled/*.conf" >> /usr/local/apache2/conf/httpd.conf

# Set ServerName to suppress warning
RUN echo "ServerName localhost" >> /usr/local/apache2/conf/httpd.conf

# Create vhosts directory
RUN mkdir -p /etc/apache2/sites-enabled

WORKDIR /var/www/html

EXPOSE 80 443

CMD ["httpd-foreground"]
