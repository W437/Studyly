// The research source policy: the sites web research must never use (research_sources.ts), and where the relay applies the list
// before any search runs (the list of sites, the environment). Its effect on a reply is tested with the rest of research, in
// assistant.test.ts.

import { assert, assertEquals } from "@std/assert";
import { RESEARCH_DOMAINS } from "../_shared/assistant.ts";
import { envFrom } from "../_shared/env.ts";
import { DENIED_SOURCES, isDeniedHost, isDeniedUrl, opensDenied, withoutDenied } from "../_shared/research_sources.ts";
import { onAllowedSite } from "../_shared/openai_assistant.ts";

Deno.test("the denied sites: OpenStax and Connexions, which forbid AI use, and the answer-selling study sites", () => {
  assertEquals([...DENIED_SOURCES], [
    "openstax.org",
    "cnx.org",
    "chegg.com",
    "coursehero.com",
    "quizlet.com",
    "studocu.com",
    "scribd.com",
    "brainly.com",
    "bartleby.com",
    "ncbi.nlm.nih.gov",
    "statpearls.com",
  ]);
  assertEquals(new Set(DENIED_SOURCES).size, DENIED_SOURCES.length);
  for (const d of DENIED_SOURCES) assert(/^[a-z0-9.-]+\.[a-z]{2,}$/.test(d), d);
});

Deno.test("a host matches by whole labels from its end: the site, its subdomains and www, in any case, with or without a final dot", () => {
  for (
    const host of [
      "openstax.org",
      "OpenStax.org",
      "www.openstax.org",
      "assets.openstax.org",
      "a.b.openstax.org",
      "openstax.org.",
      "WWW.OPENSTAX.ORG.",
      "cnx.org",
      "legacy.cnx.org",
      "www.chegg.com",
      "ncbi.nlm.nih.gov",
      "pmc.ncbi.nlm.nih.gov",
      "pubmed.ncbi.nlm.nih.gov",
      "www.ncbi.nlm.nih.gov",
      "statpearls.com",
      "www.statpearls.com",
      "quizlet.com",
      "en.quizlet.com",
      "coursehero.com",
      "studocu.com",
      "scribd.com",
      "brainly.com",
      "bartleby.com",
    ]
  ) {
    assert(isDeniedHost(host), host);
  }
  for (
    const host of [
      "notopenstax.org", // ends with the name, but is not a subdomain of it
      "openstax.org.example.net", // the name inside someone else's
      "openstax.org.evil.example",
      "openstax.com",
      "myopenstax.org",
      "chegg.org",
      "nih.gov", // NCBI is one corner of NIH: the rest is not denied
      "www.nih.gov",
      "nlm.nih.gov",
      "niddk.nih.gov",
      "myncbi.nlm.nih.gov", // ends with the name, but is not a subdomain of it
      "ncbi.nlm.nih.gov.example.net",
      "notstatpearls.com",
      "statpearls.com.evil.example",
      "wikipedia.org",
      "en.wikipedia.org",
      "khanacademy.org",
      "libretexts.org",
      "",
    ]
  ) {
    assert(!isDeniedHost(host), host);
  }
});

Deno.test("an address is denied by its host, not by its path, query or user name", () => {
  for (
    const url of [
      "https://openstax.org/books/biology/pages/11-1",
      "http://www.openstax.org/",
      "https://assets.openstax.org/oscms-prodcms/x.pdf",
      "https://OPENSTAX.ORG./books",
      "https://openstax.org:443/books",
      "https://www.quizlet.com/123/mitosis-flash-cards/",
      "https://cnx.org/contents/abc",
      "https://pubmed.ncbi.nlm.nih.gov/12345678/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC1234567/",
      "https://www.ncbi.nlm.nih.gov/books/NBK430685/",
      "https://www.statpearls.com/point-of-care/12345",
    ]
  ) {
    assert(isDeniedUrl(url), url);
  }
  for (
    const url of [
      "https://en.wikipedia.org/wiki/OpenStax",
      "https://evil.example/?next=https://openstax.org/",
      "https://evil.example/openstax.org",
      "https://openstax.org@evil.example/", // the host is evil.example
      "https://notopenstax.org/",
      "https://openstax.org.evil.example/",
      "https://www.niddk.nih.gov/health-information/diabetes",
      "https://medlineplus.gov/diabetes.html",
      "not an address",
      "",
    ]
  ) {
    assert(!isDeniedUrl(url), url);
  }
});

Deno.test("withoutDenied takes the denied sites and their subdomains out of an allow-list, in order", () => {
  assertEquals(
    withoutDenied([
      "wikipedia.org",
      "openstax.org",
      "ocw.mit.edu",
      "assets.openstax.org",
      "quizlet.com",
      "ncbi.nlm.nih.gov",
      "pmc.ncbi.nlm.nih.gov",
      "niddk.nih.gov",
    ]),
    ["wikipedia.org", "ocw.mit.edu", "niddk.nih.gov"],
  );
  assertEquals(withoutDenied(["openstax.org", "cnx.org"]), []);
  assertEquals(withoutDenied([]), []);
});

Deno.test("an allow-list entry opens a denied site when it is the site, under it, or a parent of it", () => {
  for (
    const entry of [
      "openstax.org",
      "assets.openstax.org",
      "WWW.OpenStax.org",
      "ncbi.nlm.nih.gov",
      "pmc.ncbi.nlm.nih.gov",
      "nlm.nih.gov", // a parent of ncbi.nlm.nih.gov
      "nih.gov", // a parent too: the search would read PubMed and PMC and only the links would be hidden
      "www.nih.gov",
      "NIH.gov",
      "org", // a bare top-level domain holds them all
      "com",
      "gov",
    ]
  ) {
    assert(opensDenied(entry), entry);
  }
  for (
    const entry of [
      "niddk.nih.gov",
      "nhlbi.nih.gov",
      "ods.od.nih.gov",
      "od.nih.gov",
      "cancer.gov",
      "medlineplus.gov",
      "myncbi.nlm.nih.gov",
      "ncbi.nlm.nih.gov.example.net",
      "wikipedia.org",
      "www.gov.uk",
      "edu",
    ]
  ) {
    assert(!opensDenied(entry), entry);
  }
  assertEquals(
    withoutDenied(["nih.gov", "nlm.nih.gov", "niddk.nih.gov", "ncbi.nlm.nih.gov", "quizlet.com", "wikipedia.org"]),
    ["niddk.nih.gov", "wikipedia.org"],
  );
});

Deno.test("the built-in research sites hold no denied site", () => {
  assertEquals(withoutDenied(RESEARCH_DOMAINS), [...RESEARCH_DOMAINS]);
  assert(!RESEARCH_DOMAINS.includes("openstax.org"));
  // The sites the search can still reach include Wikipedia and the public bodies research prefers.
  for (const open of ["wikipedia.org", "nhlbi.nih.gov", "cdc.gov", "plos.org", "gutenberg.org"]) {
    assert(RESEARCH_DOMAINS.includes(open), open);
  }
  // NIH is there by institute, never as nih.gov, which would open NCBI's PubMed, PMC and Bookshelf as well.
  assert(!RESEARCH_DOMAINS.includes("nih.gov"));
  for (
    const institute of [
      "niddk",
      "nhlbi",
      "nia",
      "niaid",
      "nimh",
      "ninds",
      "nigms",
      "nei",
      "nichd",
      "nccih",
    ]
  ) {
    assert(RESEARCH_DOMAINS.includes(`${institute}.nih.gov`), institute);
  }
  assert(RESEARCH_DOMAINS.includes("ods.od.nih.gov") && RESEARCH_DOMAINS.includes("cancer.gov"));
  assert(!RESEARCH_DOMAINS.some((d) => isDeniedHost(d) || d === "nih.gov" || d.endsWith(".nlm.nih.gov")));
});

Deno.test("onAllowedSite refuses a denied page even when its site is on the list it is given", () => {
  const domains = ["openstax.org", "wikipedia.org"];
  assert(!onAllowedSite("https://openstax.org/books/biology", domains));
  assert(!onAllowedSite("https://assets.openstax.org/x", domains));
  assert(onAllowedSite("https://en.wikipedia.org/wiki/Mitosis", domains));
});

Deno.test("an entry may be a whole site or one host: www.gov.uk is GOV.UK and not the councils' sites", () => {
  assert(onAllowedSite("https://www.gov.uk/government/organisations", RESEARCH_DOMAINS));
  assert(onAllowedSite("https://www.legislation.gov.uk/ukpga/2010/15/contents", RESEARCH_DOMAINS));
  assert(!onAllowedSite("https://www.hertfordshire.gov.uk/services", RESEARCH_DOMAINS));
  assert(!onAllowedSite("https://gov.uk.evil.example/", RESEARCH_DOMAINS));
  assert(onAllowedSite("https://www.wikipedia.org/", RESEARCH_DOMAINS), "www is the site's own subdomain");
  assert(onAllowedSite("https://www.nhlbi.nih.gov/health/heart", RESEARCH_DOMAINS));
  assert(onAllowedSite("https://ods.od.nih.gov/factsheets/VitaminD-Consumer/", RESEARCH_DOMAINS));
  assert(onAllowedSite("https://www.cancer.gov/about-cancer", RESEARCH_DOMAINS));
  // The rest of NIH is not open: PubMed, PMC and Bookshelf (with StatPearls) keep their own licences.
  for (
    const url of [
      "https://www.nih.gov/health-information",
      "https://pubmed.ncbi.nlm.nih.gov/12345678/",
      "https://pmc.ncbi.nlm.nih.gov/articles/PMC123/",
      "https://www.ncbi.nlm.nih.gov/books/NBK430685/",
      "https://www.statpearls.com/point-of-care/12345",
      "https://medlineplus.gov/diabetes.html",
    ]
  ) {
    assert(!onAllowedSite(url, RESEARCH_DOMAINS), url);
  }
  // What was dropped from the list is not shown, whoever vouches for it in the search.
  for (
    const url of [
      "https://www.britannica.com/science/meiosis",
      "https://www.khanacademy.org/science/biology",
      "https://www.mayoclinic.org/diseases-conditions",
      "https://ocw.mit.edu/courses/biology/",
      "https://arxiv.org/abs/2401.00001",
    ]
  ) {
    assert(!onAllowedSite(url, RESEARCH_DOMAINS), url);
  }
});

const get = (v: Record<string, string>) => (name: string) => v[name] ?? "";

Deno.test("RESEARCH_DOMAINS cannot bring a denied site back: it is taken out and a cold-start fault says so", () => {
  const env = envFrom(get({ RESEARCH_DOMAINS: "wikipedia.org, OpenStax.org, assets.openstax.org, example.edu" }));
  assertEquals(env.researchDomains, ["wikipedia.org", "example.edu"]);
  assert(env.faults.includes("research_domains_denied"));

  // A list that was only denied sites would leave nothing to search: the built-in list stands in, with the same fault.
  const only = envFrom(get({ RESEARCH_DOMAINS: "openstax.org cnx.org" }));
  assertEquals(only.researchDomains, [...RESEARCH_DOMAINS]);
  assert(only.faults.includes("research_domains_denied"));

  const ncbi = envFrom(
    get({ RESEARCH_DOMAINS: "nhlbi.nih.gov, ncbi.nlm.nih.gov, pubmed.ncbi.nlm.nih.gov, statpearls.com" }),
  );
  assertEquals(ncbi.researchDomains, ["nhlbi.nih.gov"]);
  assert(ncbi.faults.includes("research_domains_denied"));

  // A parent of a denied host is dropped too: "nih.gov" would let the search read PubMed and PMC, whose links are only hidden
  // afterwards.
  const parent = envFrom(get({ RESEARCH_DOMAINS: "nih.gov, nlm.nih.gov, nhlbi.nih.gov, wikipedia.org" }));
  assertEquals(parent.researchDomains, ["nhlbi.nih.gov", "wikipedia.org"]);
  assert(parent.faults.includes("research_domains_denied"));
  const onlyParent = envFrom(get({ RESEARCH_DOMAINS: "nih.gov" }));
  assertEquals(onlyParent.researchDomains, [...RESEARCH_DOMAINS]);
  assert(onlyParent.faults.includes("research_domains_denied"));

  // Nothing denied, nothing said.
  assert(!envFrom(get({ RESEARCH_DOMAINS: "example.edu, foo.org" })).faults.includes("research_domains_denied"));
  assert(!envFrom(get({})).faults.includes("research_domains_denied"));
});
