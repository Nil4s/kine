import csv, json, math, sys

import statistics
def pc(v,p):
    s=sorted(v); k=(len(s)-1)*p/100.0; f=int(k); c=min(f+1,len(s)-1)
    return s[f]+(s[c]-s[f])*(k-f)
def ols(X,y):
    n=len(X[0]); A=[[sum(r[i]*r[j] for r in X) for j in range(n)] for i in range(n)]; b=[sum(r[i]*yy for r,yy in zip(X,y)) for i in range(n)]
    for i in range(n):
        p=max(range(i,n),key=lambda r:abs(A[r][i])); A[i],A[p]=A[p],A[i]; b[i],b[p]=b[p],b[i]
        for r in range(i+1,n):
            f=A[r][i]/A[i][i]; A[r]=[a-f*c for a,c in zip(A[r],A[i])]; b[r]-=f*b[i]
    x=[0]*n
    for i in reversed(range(n)): x[i]=(b[i]-sum(A[i][j]*x[j] for j in range(i+1,n)))/A[i][i]
    return x
src = sys.argv[1]; out = sys.argv[2]
res = {}
SKIP=("subjectid","subjectnumericrace","dodrace","age","heightin","weightlbs","writingpreference")
for sex, fn in (("male","m.csv"),("female","f.csv")):
    with open(src + "/" + fn, newline="", encoding="latin-1") as f:
        rows = list(csv.DictReader(f))
    d = {}
    for c in rows[0].keys():
        if not c or c in SKIP: continue
        try: d[c] = [float(r[c]) for r in rows]
        except Exception: pass
    r = {"n": len(rows), "dims": {}}
    for c, v in d.items():
        r["dims"][c] = {"mean": statistics.fmean(v), "sd": statistics.stdev(v), "p1": pc(v,1), "p5": pc(v,5), "p50": pc(v,50), "p95": pc(v,95), "p99": pc(v,99)}
    st = [x/1000.0 for x in d["stature"]]; m = [x/10.0 for x in d["weightkg"]]
    lm=[math.log(x) for x in m]; ls=[math.log(x) for x in st]
    bmi = [a/b**2 for a,b in zip(m,st)]
    r["derived"] = {"mass_kg_p5": pc(m,5), "mass_kg_p50": pc(m,50), "mass_kg_p95": pc(m,95), "mass_kg_mean": statistics.fmean(m),
                    "ln_mass_sd": statistics.stdev(lm), "bmi_mean": statistics.fmean(bmi),
                    "stature_m_p5": pc(st,5), "stature_m_p50": pc(st,50), "stature_m_p95": pc(st,95),
                    "b_lnmass_on_lnstat": ols([[1,x] for x in ls], lm)[1]}
    for k, c in (("biacromial_over_stature","biacromialbreadth"),("hipbreadth_over_stature","hipbreadth"),("cervicale_over_stature","cervicaleheight"),
                 ("bideltoid_over_stature","bideltoidbreadth")):
        r["derived"][k] = statistics.fmean(d[c])/statistics.fmean(d["stature"])
    X = [[1,a,b] for a,b in zip(lm,ls)]
    el = {}
    for c in d:
        if "circumference" in c:
            el[c] = ols(X, [math.log(x) for x in d[c]])[1]
    r["derived"]["elasticity"] = el
    res[sex] = r
json.dump(res, open(out,"w"), indent=1)
print({s: res[s]["n"] for s in res}); print(sorted(res["male"]["dims"].keys()))
