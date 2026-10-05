#!/bin/sh
set -eu
pkg="@pkg@"
prefix="${UUSEC_WAF_PREFIX:-/uuwaf}"
state="${UUSEC_WAF_STATE:-/var/lib/uusec-waf}"
cache="${UUSEC_WAF_CACHE:-/var/cache/uusec-waf}"
resolver="${UUSEC_WAF_RESOLVER:-}"
ipv6="${UUSEC_WAF_IPV6:-off}"
version=$(cat "$pkg/.version")

mkdir -p \
  "$state/logs" \
  "$state/acme" \
  "$state/web/conf" \
  "$state/conf" \
  "$cache" \
  "$prefix/html/.well-known/acme-challenge" \
  "$prefix/client_body_temp" \
  "$prefix/proxy_temp" \
  "$prefix/fastcgi_temp" \
  "$prefix/scgi_temp" \
  "$prefix/uwsgi_temp" \
  "$prefix/web"

if [ ! -e "$state/conf/uuwaf.conf" ]; then
  cp -a "$pkg/conf/." "$state/conf/"
fi
install -m 644 "$pkg/conf/geoip.mmdb" "$state/conf/geoip.mmdb"
printf '%s\n' "$version" > "$state/conf/.stock-version"

if [ -z "$resolver" ]; then
  resolver=$(awk '/^nameserver[[:space:]]/{ print $2; exit }' /etc/resolv.conf || true)
  if [ -z "$resolver" ]; then
    resolver="1.1.1.1"
  fi
fi
printf 'resolver %s valid=30s ipv6=%s;\n' "$resolver" "$ipv6" > "$state/conf/resolver.conf"

ln -sfn "$state/conf" "$prefix/conf"
ln -sfn "$state/logs" "$prefix/logs"
ln -sfn "$state/acme" "$prefix/acme"
ln -sfn "$state/web/conf" "$prefix/web/conf"

for name in sbin luajit waf; do
  ln -sfn "$pkg/$name" "$prefix/$name"
done

# waf-service resolves its own path and writes next to it. A symlink would
# send those writes into the Nix store. captcha and lego are copied for the
# same reason.
cp -a "$pkg/waf-service" "$prefix/waf-service"
cp -a "$pkg/lego" "$prefix/lego"
rm -rf "$prefix/captcha"
mkdir -p "$prefix/captcha"
cp -a "$pkg/captcha/." "$prefix/captcha/"

for file in "$pkg"/html/*; do
  base=$(basename "$file")
  if [ "$base" = ".well-known" ]; then
    continue
  fi
  ln -sfn "$file" "$prefix/html/$base"
done

chmod 755 \
  "$prefix" \
  "$prefix/client_body_temp" \
  "$prefix/proxy_temp" \
  "$prefix/fastcgi_temp" \
  "$prefix/scgi_temp" \
  "$prefix/uwsgi_temp"
