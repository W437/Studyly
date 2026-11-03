// Sites web research must never use, whatever the allow-list says. Their terms forbid feeding their pages to AI services
// (OpenStax and Connexions: no ingestion into LLMs or generative-AI offerings without permission), or they sell answers
// or sit behind a paywall, or their items carry licences that do not allow this use: NCBI (PubMed, PubMed Central and
// Bookshelf) holds items under their own terms, among them StatPearls, which is non-commercial and no-derivatives. The one
// list is applied three ways:
//   - what the model is told: researchSystem() in prompts.ts names the sites;
//   - what the search tool may open: OpenAI's web_search takes only an allow-list (`allowed_domains`), so every entry that
//     would open a denied site (the site, a host under it, or a parent of it: "nih.gov" holds "ncbi.nlm.nih.gov") is taken
//     out of that list, in env.ts (the built-in list and a RESEARCH_DOMAINS secret) and again in the provider;
//   - what the student is shown: openai_assistant.ts drops a denied page from the sources and the citations of a reply, and
//     withholds a reply whose pages were all denied.
// A host matches by whole labels from its end: "openstax.org" and "assets.openstax.org" match; "notopenstax.org" and
// "openstax.org.example.net" do not.

export const DENIED_SOURCES: readonly string[] = [
  "openstax.org",
  "cnx.org",
  "chegg.com",
  "coursehero.com",
  "quizlet.com",
  "studocu.com",
  "scribd.com",
  "brainly.com",
  "bartleby.com",
  "ncbi.nlm.nih.gov", // PubMed, PubMed Central, Bookshelf: every item keeps its own licence, some non-commercial or no-derivatives
  "statpearls.com", // StatPearls: CC BY-NC-ND
];

/** A host in one form: lower case, no trailing dot (a valid way to write a name) and no leading "www.". */
function bareHost(host: string): string {
  return host.toLowerCase().replace(/\.+$/, "").replace(/^www\./, "");
}

/** The host is a denied site or a subdomain of one. */
export function isDeniedHost(host: string): boolean {
  const h = bareHost(host);
  return DENIED_SOURCES.some((d) => h === d || h.endsWith(`.${d}`));
}

/** The address is on a denied site. An address that cannot be read is not (the allow-list refuses it anyway). */
export function isDeniedUrl(url: string): boolean {
  try {
    return isDeniedHost(new URL(url).hostname);
  } catch {
    return false;
  }
}

/** An allow-list entry that would let the search read a denied site: the site itself, a host under it, or a parent of it
 * ("nih.gov" holds "ncbi.nlm.nih.gov", and a bare "org" would hold them all). Hiding the links afterwards is not enough: the
 * model would already have read the pages. */
export function opensDenied(entry: string): boolean {
  const e = bareHost(entry);
  return isDeniedHost(e) || DENIED_SOURCES.some((d) => d.endsWith(`.${e}`));
}

/** The allow-list without any entry that opens a denied site: what the search tool is given. */
export function withoutDenied(domains: readonly string[]): string[] {
  return domains.filter((d) => !opensDenied(d));
}
