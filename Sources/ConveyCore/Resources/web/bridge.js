const _turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });

window.htmlToMarkdown = (html) => _turndown.turndown(html);

window.markdownToHtml = (md) => marked.parse(md);

window.htmlToPlainText = (html) => {
  // A detached div has no layout, so innerText would return empty and we'd
  // silently fall back to textContent (which mashes block elements together
  // with no line breaks). Remote loads are blocked by the WKContentRuleList
  // (see WebRuntime), so it's safe to attach to the real document body here.
  const el = document.createElement("div");
  el.innerHTML = html;
  document.body.appendChild(el);
  const text = el.innerText || el.textContent || "";
  document.body.removeChild(el);
  return text;
};

if (window.mermaid) {
  mermaid.initialize({ startOnLoad: false });
}

window.mermaidToSvg = async (src) => {
  const id = "conv" + (window._n = (window._n || 0) + 1);
  const { svg } = await mermaid.render(id, src);
  return svg;
};

window.mermaidToPngDataUrl = async (src, scale) => {
  const id = "conv" + (window._n = (window._n || 0) + 1);
  const { svg } = await mermaid.render(id, src);
  const url = "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svg)));
  const img = new Image();
  await new Promise((resolve, reject) => {
    img.onload = resolve;
    img.onerror = reject;
    img.src = url;
  });
  const s = scale || 2;
  const w = img.width || 800;
  const h = img.height || 600;
  const canvas = document.createElement("canvas");
  canvas.width = w * s;
  canvas.height = h * s;
  const ctx = canvas.getContext("2d");
  ctx.scale(s, s);
  ctx.drawImage(img, 0, 0);
  return canvas.toDataURL("image/png");
};
