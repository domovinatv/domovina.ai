#!/usr/bin/env python3
"""Search quality harness: lokalni sloj (replika search_overlay.dart), Meili, /api/search."""
import ast, glob, json, os, sys, time, unicodedata, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

D = "."  # radni direktorij s korpusom (fetch-corpus.sh)
QUERIES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "queries.txt")
MEILI = "https://search.domovina.ai/indexes/episodes/search"
KEY = "d4e39f13270b43c3210cfa005d80fdd3390fc7948be0db0c0f03d3cffa4a780f"
RAG = "https://mcp.domovina.ai/api/search"

FOLD = {"č": "c", "ć": "c", "š": "s", "ž": "z", "đ": "d", "ø": "o", "ö": "o", "ü": "u", "ä": "a", "é": "e", "á": "a", "í": "i", "ó": "o", "ú": "u"}


def fold(s):
    return "".join(FOLD.get(c, c) for c in s.lower())


def lst(v):
    if isinstance(v, list):
        return v
    try:
        return ast.literal_eval(v) if v else []
    except Exception:
        return []


# --- lokalni indeks (kao _index u search_overlay.dart) ---
corpus = json.load(open(f"{D}/search.json"))["episodes"]
idx, titles = [], {}
for f in glob.glob(f"{D}/ch/*.json"):
    ch = json.load(open(f))
    for v in ch.get("videos", []):
        title = v.get("title_hr") or v.get("title") or ""
        titles[v["id"]] = title
        sp = [s.get("suggested_name", "") if isinstance(s, dict) else str(s) for s in lst(v.get("speakers"))]
        c = corpus.get(v["id"], {})
        topics = lst(v.get("topics")) or lst(c.get("t"))
        abstract = v.get("abstract") or c.get("a") or ""
        if not sp:
            sp = lst(c.get("s"))
        idx.append(dict(id=v["id"], ch=ch["name"], title=fold(title), sp=fold("  ".join(sp)),
                        all=fold("  ".join([title, v.get("title", ""), " ".join(sp), " ".join(topics), abstract, ch["name"]]))))


def score(tokens, hay):
    t = 0.0
    for tok in tokens:
        i = hay.find(tok)
        if i < 0:
            return 0
        t += 2.0 if i == 0 or hay[i - 1] == " " else 1.0
        t += len(tok) / 20
    return t


def local(q):
    toks = fold(q).split()
    out = []
    for e in idx:
        b = score(toks, e["all"])
        if b <= 0:
            continue
        it, isp = score(toks, e["title"]) > 0, score(toks, e["sp"]) > 0
        out.append((b + (6 if it else 0) + (3 if isp else 0), e["id"], "T" if it or isp else "t"))
    out.sort(key=lambda x: -x[0])
    return len(out), [(i, k) for _, i, k in out[:8]]


def meili(q):
    body = json.dumps({"q": q, "limit": 12, "attributesToRetrieve": ["youtube_id", "title", "channel"],
                       "attributesToHighlight": ["title", "section_titles"], "showRankingScore": True}).encode()
    r = urllib.request.Request(MEILI, body, {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json", "User-Agent": "Mozilla/5.0", "Origin": "https://domovina.ai"})
    t = time.time()
    j = json.load(urllib.request.urlopen(r, timeout=15))
    ms = int((time.time() - t) * 1000)
    hits = [(h["youtube_id"], h.get("title", ""), round(h.get("_rankingScore", 0), 2), h["_formatted"].get("title", "")) for h in j["hits"]]
    return j.get("estimatedTotalHits"), ms, hits


def sem(q):
    u = RAG + "?" + urllib.parse.urlencode({"q": q, "limit": 12})
    r = urllib.request.Request(u, headers={"Origin": "https://domovina.ai", "User-Agent": "Mozilla/5.0"})
    t = time.time()
    j = json.load(urllib.request.urlopen(r, timeout=30))
    ms = int((time.time() - t) * 1000)
    seen, out = set(), []
    for x in j.get("results", []):
        if x["youtube_id"] in seen:
            continue
        seen.add(x["youtube_id"])
        kind = "S" if x["start_ts"] == 0 and x["end_ts"] == 0 else f"{int(x['start_ts'])}s"
        out.append((x["youtube_id"], x.get("episode_title") or "", round(x["score"], 3), kind, x["text"][:110].replace("\n", " ")))
    return ms, out


def t(i):
    return (titles.get(i) or "?")[:70]


def main():
    queries = [l.strip() for l in open(QUERIES) if l.strip() and not l.startswith("#")]
    
    
    def run(q):
        try:
            m = meili(q)
        except Exception as e:
            m = (None, 0, [("ERR", str(e)[:80], 0, "")])
        try:
            s = sem(q)
        except Exception as e:
            s = (0, [("ERR", str(e)[:80], 0, "", "")])
        return q, local(q), m, s
    
    
    with ThreadPoolExecutor(3) as ex:
        res = list(ex.map(run, queries))
    
    print(f"lokalni indeks: {len(idx)} epizoda\n")
    for q, (ln, lh), (mt, mms, mh), (sms, sh) in res:
        print("=" * 100)
        print(f"Q: {q!r}")
        print(f"  LOKALNO  ({ln} pogodaka)")
        for i, k in lh[:5]:
            print(f"    [{k}] {i} {t(i)}")
        print(f"  MEILI    ({mt} pogodaka, {mms} ms)")
        for i, ti, sc, ft in mh[:5]:
            print(f"    {sc:4} {i} {ti[:70]}   «{ft[:60]}»" if "<em>" in ft else f"    {sc:4} {i} {ti[:70]}")
        print(f"  SEMANTIKA ({sms} ms)")
        for i, ti, sc, kind, tx in sh[:5]:
            print(f"    {sc} {kind:>6} {i} {ti[:60]}")
            print(f"           └ {tx}")

if __name__ == "__main__":
    main()
