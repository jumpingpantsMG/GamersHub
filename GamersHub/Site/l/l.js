//
//  l.js
//  GamersHub
//
//  Created by Jaiden Kumar on 14/11/26.
//


// Public page for a shared listing. Everything from the database is inserted as text, never as HTML.
const SUPABASE_URL = "https://qyfzhgqrvkbviipfglsk.supabase.co";
const SUPABASE_KEY = "sb_publishable_GX19kgYWlnb1J3cuZczOWg_0fYbWvk-"; // public key, safe to ship

const out = document.getElementById("out");
const id = new URLSearchParams(location.search).get("id") || "";

function el(tag, props = {}, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") n.className = v; else n.setAttribute(k, v);
  }
  for (const kid of kids) if (kid) n.append(kid instanceof Node ? kid : document.createTextNode(kid));
  return n;
}
const show = (...nodes) => out.replaceChildren(...nodes);

async function main() {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    return show(el("p", {}, "That link doesn't look right."));
  }
  const q = `${SUPABASE_URL}/rest/v1/listings?id=eq.${id}&select=title,description,category,image_url,avg_rating,rating_count,url,age_rating,is_verified&limit=1`;
  let rows;
  try {
    const res = await fetch(q, { headers: { apikey: SUPABASE_KEY } });
    rows = await res.json();
  } catch { return show(el("p", {}, "Couldn't load this listing. Try again.")); }
  const l = Array.isArray(rows) && rows[0];
  if (!l) return show(el("p", {}, "This listing isn't available anymore."));

  const adult = l.age_rating >= 17;
  const rating = l.rating_count > 0 ? `★ ${Number(l.avg_rating).toFixed(1)} (${l.rating_count})` : "No reviews yet";
  const safeHttps = (u) => { try { return new URL(u).protocol === "https:" ? u : null; } catch { return null; } };
  const cover = !adult && safeHttps(l.image_url);
  const site = safeHttps(l.url);

  document.title = l.title + " on GamersHub";
  show(el("div", { class: "card" },
    cover && el("img", { src: cover, alt: "", referrerpolicy: "no-referrer" }),
    el("div", { class: "body" },
      el("h1", {}, l.title),
      el("div", { class: "tags" },
        el("span", { class: "tag" }, l.category),
        el("span", { class: "tag" }, rating),
        el("span", { class: "tag" }, l.age_rating + "+"),
        l.is_verified && el("span", { class: "tag ok" }, "Verified")),
      el("p", {}, l.description),
      el("div", { class: "btns" },
        el("a", { class: "btn main", href: "gamershub://listing/" + id }, "Open in GamersHub"),
        site && el("a", { class: "btn", href: site, rel: "noopener noreferrer nofollow" }, "Visit site")))));
}
main();