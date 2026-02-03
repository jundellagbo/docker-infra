# PHP Version (can be: 7.4, 8.0, 8.1, 8.2, 8.3, 8.4)
ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-fpm-alpine

# Install dependencies for WordPress and general PHP development
RUN apk add --no-cache \
    # Build tools
    $PHPIZE_DEPS \
    # General utilities
    curl \
    git \
    zip \
    unzip \
    less \
    # Database clients
    mysql-client \
    # Libraries for PHP extensions
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    libwebp-dev \
    freetype-dev \
    oniguruma-dev \
    libxml2-dev \
    postgresql-dev \
    icu-dev \
    imagemagick-dev \
    libsodium-dev \
    libmemcached-dev \
    zlib-dev \
    bzip2-dev \
    libxslt-dev \
    gettext-dev \
    gmp-dev \
    tidyhtml-dev \
    openssl-dev \
    linux-headers

# Configure and install PHP extensions for WordPress
RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        # WordPress Required
        mysqli \
        # WordPress Strongly Recommended
        curl \
        dom \
        exif \
        fileinfo \
        intl \
        mbstring \
        xml \
        zip \
        # WordPress Caching
        opcache \
        # WordPress Recommended
        bcmath \
        filter \
        gd \
        iconv \
        sodium \
        # Database
        pdo \
        pdo_mysql \
        pdo_pgsql \
        pgsql \
        # Additional useful extensions
        soap \
        pcntl \
        sockets \
        bz2 \
        xsl \
        gettext \
        gmp \
        tidy \
        calendar \
        shmop \
        sysvmsg \
        sysvsem \
        sysvshm

# Install PECL extensions
RUN pecl install redis && docker-php-ext-enable redis \
    && pecl install imagick && docker-php-ext-enable imagick \
    && pecl install apcu && docker-php-ext-enable apcu \
    && pecl install igbinary && docker-php-ext-enable igbinary \
    && pecl install memcached --with-memcached-igbinary=yes && docker-php-ext-enable memcached

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Configure PHP
RUN echo "memory_limit=512M" > /usr/local/etc/php/conf.d/memory-limit.ini \
    && echo "upload_max_filesize=100M" >> /usr/local/etc/php/conf.d/uploads.ini \
    && echo "post_max_size=100M" >> /usr/local/etc/php/conf.d/uploads.ini \
    && echo "max_execution_time=600" >> /usr/local/etc/php/conf.d/execution.ini

# Configure sendmail to use MailHog
RUN echo "sendmail_path = /usr/sbin/sendmail -S mailhog:1025" > /usr/local/etc/php/conf.d/mailhog.ini

# Create www-data user with correct permissions
RUN addgroup -g 1000 -S www && adduser -u 1000 -S www -G www

WORKDIR /var/www

USER www-data

EXPOSE 9000

CMD ["php-fpm"]
