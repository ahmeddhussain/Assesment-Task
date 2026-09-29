FROM nginxinc/nginx-unprivileged:alpine

USER root
RUN rm -rf /usr/share/nginx/html/*
COPY index.html /usr/share/nginx/html/

USER nginx
EXPOSE 8080

# ADDED: Healthcheck for Nginx (hits its own localhost to ensure it is serving the page)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]