"""Snimi sirove odgovore produkcije za old/new varijantu klijenta → fixtures.json"""
import json, urllib.request, urllib.parse, time
from run import QUERIES, fold, idx, score, titles
K="d4e39f13270b43c3210cfa005d80fdd3390fc7948be0db0c0f03d3cffa4a780f"
H={"Authorization":"Bearer "+K,"Content-Type":"application/json","User-Agent":"Mozilla/5.0","Origin":"https://domovina.ai"}
STOP=set("a ali bi bio bila biti da do gdje i ili iz je jesu k ka kad kada kako koja koje kojeg koji li mi na ne ni o od po pri s sa sam se si smo ste sta sto su ta te ti tko to u uz vi za zasto".split())
def content(q):
    w=[x for x in q.split() if fold(x) not in STOP]; return " ".join(w) if w else q
def meili(q, strat=None):
    b={"q":q,"limit":12,"attributesToRetrieve":["youtube_id","title","channel","upload_date","section_titles","deep_link"],
       "attributesToHighlight":["title","article_text","section_titles"],"attributesToCrop":["article_text"],"cropLength":32}
    if strat: b["matchingStrategy"]=strat
    return json.load(urllib.request.urlopen(urllib.request.Request("https://search.domovina.ai/indexes/episodes/search",json.dumps(b).encode(),H),timeout=20))
def sem(q):
    return json.load(urllib.request.urlopen(urllib.request.Request("https://mcp.domovina.ai/api/search?"+urllib.parse.urlencode({"q":q,"limit":12}),headers=H),timeout=30))
def scoreN(tokens,hay):
    t=0.0
    for tok in tokens:
        i=hay.find(tok)
        if i<0 and 'dj' in tok: i=hay.find(tok.replace('dj','d'))
        if i<0: return 0
        t+=2.0 if i==0 or hay[i-1]==' ' else 1.0; t+=len(tok)/20
    return t
def local(q,new):
    toks=fold(content(q) if new else q).split(); f=scoreN if new else score; out=[]
    for e in idx:
        b=f(toks,e["all"])
        if b<=0: continue
        it,isp=f(toks,e["title"])>0,f(toks,e["sp"])>0
        out.append((b+(6 if it else 0)+(3 if isp else 0),e["id"],it or isp,e["ch"]))
    out.sort(key=lambda x:-x[0])
    return [dict(id=i,title=titles[i],channel=c,titleMatch=t) for _,i,t,c in out[:12]]
def main():
    qs=[l.strip() for l in open(QUERIES) if l.strip() and not l.startswith("#")]
    fx=[]
    for q in qs:
        s=sem(q)
        fx.append(dict(query=q,semantic=s,
            old=dict(local=local(q,False),meili=meili(q)),
            new=dict(local=local(q,True),meili=meili(content(q),"all"))))
        print(q, len(fx[-1]["old"]["meili"]["hits"]), len(fx[-1]["new"]["meili"]["hits"]), flush=True)
    json.dump(fx,open("fixtures.json","w"),ensure_ascii=False)
if __name__=="__main__":
    main()
