//
//  admin.js
//  GamersHub
//
//  Created by Jaiden Kumar on 13/11/26.
//


// GamersHub admin. Safe by design: every user-written string is inserted with textContent
// (never innerHTML), and the database only lets people in the `admins` table do anything here.

const SUPABASE_URL = "https://qyfzhgqrvkbviipfglsk.supabase.co";
const SUPABASE_KEY = "sb_publishable_GX19kgYWlnb1J3cuZczOWg_0fYbWvk-"; // public key, safe to ship

const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
const app = document.getElementById("app");

function el(tag, props = {}, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") n.className = v;
    else if (k === "onclick") n.addEventListener("click", v);
    else if (v !== undefined && v !== null) n.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid === null || kid === undefined || kid === false) continue;
    n.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return n;
}
const mount = (...nodes) => app.replaceChildren(...nodes);
const when = (iso) => (iso ? new Date(iso).toLocaleString() : "");

let tab = "reports";
let showResolved = false;

// ---------- Sign in ----------
function renderLogin(message) {
  const email = el("input", { type: "email", placeholder: "Email", autocomplete: "username" });
  const pass = el("input", { type: "password", placeholder: "Password", autocomplete: "current-password" });
  const err = el("div", { class: "err" }, message || "");
  const go = async () => {
    err.textContent = "";
    const { error } = await db.auth.signInWithPassword({ email: email.value.trim(), password: pass.value });
    if (error) err.textContent = error.message;
    else boot();
  };
  pass.addEventListener("keydown", (e) => { if (e.key === "Enter") go(); });
  mount(el("div", { class: "login" },
    el("h1", {}, "GamersHub Admin"),
    email, pass, el("button", { class: "active", onclick: go }, "Sign in"), err));
}

// ---------- Shell ----------
function renderShell(content) {
  const tabBtn = (id, label) =>
    el("button", { class: tab === id ? "active" : "", onclick: () => { tab = id; show(); } }, label);
  mount(
    el("header", {},
      el("h1", {}, "GamersHub Admin"),
      el("div", { class: "tabs" }, tabBtn("reports", "Reports"), tabBtn("listings", "Listings"), tabBtn("admins", "Admins")),
      el("div", { class: "spacer" }),
      el("button", { onclick: async () => { await db.auth.signOut(); boot(); } }, "Sign out")),
    el("main", {}, content));
}

async function act(promise) {
  const { error } = await promise;
  if (error) alert(error.message);
  await show();
}

// ---------- Reports ----------
async function reportsView() {
  const { data, error } = await db.from("reports")
    .select("id, reason, note, created_at, resolved_at, listing_id, review_id, listings(id, title, url, is_hidden), reviews(id, stars, comment, is_hidden)")
    .order("created_at", { ascending: false }).limit(200);
  if (error) return el("div", { class: "err" }, error.message);

  const rows = data.filter((r) => showResolved || !r.resolved_at);
  const toggle = el("button", { onclick: () => { showResolved = !showResolved; show(); } },
    showResolved ? "Hide resolved" : "Show resolved");
  const out = [el("div", { class: "row", style: "margin-bottom:12px" },
    el("strong", {}, `${rows.length} report${rows.length === 1 ? "" : "s"}`), el("span", { class: "spacer" }), toggle)];

  if (!rows.length) out.push(el("p", { class: "muted" }, "Nothing to review."));

  for (const r of rows) {
    const l = r.listings, rv = r.reviews;
    out.push(el("div", { class: "card" },
      el("div", { class: "row" },
        el("strong", {}, r.reason),
        r.review_id ? el("span", { class: "tag" }, "review") : el("span", { class: "tag" }, "listing"),
        r.resolved_at && el("span", { class: "tag green" }, "resolved"),
        el("span", { class: "spacer" }),
        el("span", { class: "muted" }, when(r.created_at))),
      r.note && el("div", { class: "quote" }, r.note),
      l && el("div", { class: "muted" }, "Listing: ", l.title, " · ", l.url, " ",
        l.is_hidden && el("span", { class: "tag red" }, "hidden")),
      rv && el("div", { class: "quote" }, `${"★".repeat(rv.stars)} ${rv.comment || "(no comment)"}`,
        rv.is_hidden ? "  [hidden]" : ""),
      el("div", { class: "row", style: "margin-top:10px" },
        l && el("button", { class: l.is_hidden ? "ok" : "danger",
          onclick: () => act(db.rpc("admin_set_listing_hidden", { p_id: l.id, p_hidden: !l.is_hidden })) },
          l.is_hidden ? "Unhide listing" : "Hide listing"),
        rv && el("button", { class: rv.is_hidden ? "ok" : "danger",
          onclick: () => act(db.rpc("admin_set_review_hidden", { p_id: rv.id, p_hidden: !rv.is_hidden })) },
          rv.is_hidden ? "Unhide review" : "Hide review"),
        el("button", {
          onclick: () => act(db.rpc("admin_set_report_resolved", { p_id: r.id, p_resolved: !r.resolved_at })) },
          r.resolved_at ? "Reopen" : "Mark resolved"))));
  }
  return out;
}

// ---------- Listings ----------
let listingFilter = "";
async function listingsView() {
  const { data, error } = await db.from("listings")
    .select("id, title, url, category, is_hidden, is_verified, sponsored_until, created_at, click_count, rating_count")
    .order("created_at", { ascending: false }).limit(500);
  if (error) return el("div", { class: "err" }, error.message);

  const search = el("input", { placeholder: "Filter by title or URL", value: listingFilter });
  search.addEventListener("input", () => { listingFilter = search.value; draw(); });
  const holder = el("div", {});
  const draw = () => {
    const q = listingFilter.toLowerCase();
    const rows = data.filter((l) => !q || l.title.toLowerCase().includes(q) || l.url.toLowerCase().includes(q));
    holder.replaceChildren(...rows.map((l) => el("div", { class: "card" },
      el("div", { class: "row" },
        el("strong", {}, l.title),
        l.is_hidden && el("span", { class: "tag red" }, "hidden"),
        l.is_verified && el("span", { class: "tag green" }, "verified"),
        new Date(l.sponsored_until) > new Date() && el("span", { class: "tag" }, "sponsored"),
        el("span", { class: "spacer" }),
        el("button", { class: l.is_hidden ? "ok" : "danger",
          onclick: () => act(db.rpc("admin_set_listing_hidden", { p_id: l.id, p_hidden: !l.is_hidden })) },
          l.is_hidden ? "Unhide" : "Hide")),
      el("div", { class: "muted" }, l.url),
      el("div", { class: "muted" }, `${l.category} · ${l.click_count ?? 0} visits · ${l.rating_count ?? 0} reviews · ${when(l.created_at)}`))));
  };
  draw();
  return [el("div", { style: "margin-bottom:12px" }, search), holder];
}

// ---------- Admins ----------
async function adminsView() {
  const { data, error } = await db.rpc("admin_list_admins");
  if (error) return el("div", { class: "err" }, error.message);
  const { data: me } = await db.auth.getUser();

  const email = el("input", { type: "email", placeholder: "Email of a confirmed account" });
  return [
    el("div", { class: "card" },
      el("strong", {}, "Add an admin"),
      el("p", { class: "muted" }, "They must already have signed up in the app and confirmed their email."),
      el("div", { class: "row" }, email,
        el("button", { class: "active", onclick: () => act(db.rpc("admin_add_admin", { p_email: email.value })) }, "Add"))),
    ...data.map((a) => el("div", { class: "card row" },
      el("strong", {}, a.email), el("span", { class: "muted" }, "since " + when(a.created_at)),
      el("span", { class: "spacer" }),
      a.user_id !== me?.user?.id && el("button", { class: "danger",
        onclick: () => { if (confirm("Remove " + a.email + " as admin?")) act(db.rpc("admin_remove_admin", { p_user: a.user_id })); } },
        "Remove"))),
  ];
}

// ---------- Boot ----------
async function show() {
  const view = tab === "reports" ? reportsView : tab === "listings" ? listingsView : adminsView;
  renderShell(el("p", { class: "muted" }, "Loading..."));
  renderShell(await view());
}

async function boot() {
  const { data } = await db.auth.getSession();
  if (!data.session) return renderLogin();
  const { data: isAdmin } = await db.rpc("is_admin");
  if (!isAdmin) {
    await db.auth.signOut();
    return renderLogin("That account isn't an admin.");
  }
  show();
}
boot();