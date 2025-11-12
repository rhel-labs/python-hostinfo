# Start with the RHEL 10 bootable base image
FROM registry.redhat.io/rhel10/rhel-bootc:10.1

# Install necessary packages from RHEL Application Streams using dnf
# This includes default Python 3, pip, and Nginx
RUN dnf install -y \
    python3 \
    python3-pip \
    nginx && \
    dnf clean all && rm -rf /var/cache/dnf

# Copy the Flask application files and Gunicorn service file
ADD . /app
COPY info-app.service /etc/systemd/system/

# Install requirements via pip3
RUN pip3 install -r /app/requirements.txt

# --- Nginx Configuration (Example Adaptation) ---
# Copy a custom Nginx configuration file that acts as a reverse proxy
# This file needs to be created separately and configured to forward requests
# to the Gunicorn process (e.g., listening on localhost:80)
COPY info-app.conf /etc/nginx/conf.d/

# Ensure nginx can talk to gunicorn
WORKDIR /app
RUN checkmodule -M -m nginx_connect_flask_sock.te -o nginx_connect_flask_sock.mo
RUN semodule_package -o nginx_connect_flask_sock.pp -m nginx_connect_flask_sock.mo
RUN semodule -i nginx_connect_flask_sock.pp
RUN mkdir /run/flask-app && chgrp -R nginx /run/flask-app && chmod 770 /run/flask-app
RUN semanage fcontext -a -t httpd_var_run_t /run/flask-app

# Enable our application services
RUN systemctl enable nginx.service
RUN systemctl enable info-app.service
