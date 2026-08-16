FROM node@sha256:0557ac14e0d45d02ed563067b82856ca5e7aa3437fa28d98d4350ea9c3d9494a AS build

RUN git clone \
      https://github.com/markup-carve/carve-js.git /opt/carve \
    && cd /opt/carve \
    && git checkout 88158743c318d20e6a7d1b2e6c1095d75b4264c1 \
    && git submodule update --init --recursive \
    && npm ci \
    && npm run build \
    && git clone https://github.com/Omikhleia/resilient.sile.git /opt/resilient.sile \
    && cd /opt/resilient.sile \
    && git checkout 739d00222d9e983f3580b33081b5c5fb0711de2e \
    && git clone https://github.com/Omikhleia/grail.git /opt/grail \
    && cd /opt/grail && git checkout 4a7bb3fdbd14c9aa29992b7367ec8f7ad733d9d6 \
    && git clone https://github.com/Omikhleia/rough-lua.git /opt/rough \
    && cd /opt/rough && git checkout f5878a07bb0462db4ab1eb5963fdf860c3235cce \
    && mkdir -p /opt/addons \
    && git clone https://github.com/Omikhleia/barcodes.sile.git /opt/addons/barcodes.sile \
    && cd /opt/addons/barcodes.sile && git checkout f9b4ab14110c8f14d3591c859311a1598ec7cd65 \
    && git clone https://github.com/Omikhleia/couyards.sile.git /opt/addons/couyards.sile \
    && cd /opt/addons/couyards.sile && git checkout c98fb33a7696c0657dc6b57bbb3a0954c1ac694e \
    && git clone https://github.com/Omikhleia/embedders.sile.git /opt/addons/embedders.sile \
    && cd /opt/addons/embedders.sile && git checkout 17e399b742f24733dd5d64b43a24ef792aaadc77 \
    && git clone --recurse-submodules https://github.com/Omikhleia/highlighter.sile.git /opt/addons/highlighter.sile \
    && cd /opt/addons/highlighter.sile && git checkout 97d30d1773483db1d6adc33e54fb6518c945a92c \
    && git clone https://github.com/Omikhleia/labelrefs.sile.git /opt/addons/labelrefs.sile \
    && cd /opt/addons/labelrefs.sile && git checkout f3b956a61bfa101191674854fb1ba1ea052e8c5e \
    && git clone https://github.com/Omikhleia/piecharts.sile.git /opt/addons/piecharts.sile \
    && cd /opt/addons/piecharts.sile && git checkout 683700e65b8f6dd31eb492f8d650fff48cb7a5ca \
    && git clone https://github.com/Omikhleia/ptable.sile.git /opt/addons/ptable.sile \
    && cd /opt/addons/ptable.sile && git checkout 1d1b1ba9a28802fd67c06711d0577904805079dd \
    && git clone https://github.com/Omikhleia/qrcode.sile.git /opt/addons/qrcode.sile \
    && cd /opt/addons/qrcode.sile && git checkout 8ade7e43ed3e16fdc0bc88b9134e657ff355049a \
    && git clone https://github.com/Omikhleia/smartquotes.sile.git /opt/addons/smartquotes.sile \
    && cd /opt/addons/smartquotes.sile && git checkout 1b609d38ed802d3e5a0ec053e445edcf4a758d8e \
    && git clone https://github.com/Omikhleia/textsubsuper.sile.git /opt/addons/textsubsuper.sile \
    && cd /opt/addons/textsubsuper.sile && git checkout ad9f9ff41b7d0bfcda606bbb66b618e4e1bdbfcb

FROM siletypesetter/sile@sha256:3643ad31e39952fffdbbc8c058e37e9454f3c0a0d7bc51631f72823b4ccf76cf

COPY --from=build /usr/local/bin/node /usr/local/bin/node
COPY --from=build /opt/carve /opt/carve
COPY --from=build /opt/resilient.sile /opt/resilient.sile
COPY --from=build /opt/grail /opt/grail
COPY --from=build /opt/rough /opt/rough
COPY --from=build /opt/addons /opt/addons
COPY docker/carve-wrapper.sh /usr/local/bin/carve
RUN chmod +x /opt/carve/dist/cli.js \
    && chmod +x /usr/local/bin/carve \
    && luarocks install lunajson \
    && luarocks install mimetypes \
    && luarocks install sha1 \
    && cd /opt/rough && luarocks make --deps-mode=none \
    && cd /opt/grail && luarocks make --deps-mode=none \
    && for addon in /opt/addons/*; do cd "$addon" && luarocks make --deps-mode=none; done \
    && cd /opt/resilient.sile \
    && luarocks make --deps-mode=none rockspecs/resilient.sile-4.2.0-1.rockspec

WORKDIR /work
COPY . /work
RUN luarocks make carve-sile-dev-1.rockspec

CMD ["/bin/sh", "-c", "./test/renderer.sh && ./test/smoke.sh"]
