useradd \
    --system \
    --home-dir /var/lib/greetd \
    --create-home \
    --shell /sbin/nologin \
    greeter

chown greeter:greeter /var/lib/greetd
chmod 0750 /var/lib/greetd
