import pickle, sys
sys.setrecursionlimit(10000)
class DAG:
    def __init__(self): self.nodes=[]; self.memo={}; self.leafs={}
    def leaf(self,v):
        if v not in self.leafs:
            self.nodes.append(('L',v)); self.leafs[v]=len(self.nodes)-1
        return self.leafs[v]
    def node(self,key,yes,no):
        if yes==no: return yes
        k=(key,yes,no)
        if k not in self.memo:
            self.nodes.append(('N',key,yes,no)); self.memo[k]=len(self.nodes)-1
        return self.memo[k]
def build(dag, leaves):
    # leaves: list of (items(list of (key,val)), result)
    if not leaves[0][0]:
        res={r for _,r in leaves}
        assert len(res)==1, res
        return dag.leaf(res.pop())
    key=leaves[0][0][0][0]
    t=[];f=[]
    for items,r in leaves:
        assert items[0][0]==key,(key,items[0])
        (t if items[0][1] else f).append((items[1:],r))
    assert t and f, key
    return dag.node(key, build(dag,t), build(dag,f))
def make(fn):
    lv=pickle.load(open(fn,'rb'))
    dag=DAG()
    leaves=[(list(a.items()),r) for a,r in lv]
    root=build(dag,leaves)
    return dag,root
def evalset(dag,root,assign):
    out=set()
    def go(n):
        nd=dag.nodes[n]
        if nd[0]=='L': out.add(nd[1]); return
        _,key,y,no=nd
        if key in assign:
            go(y if assign[key] else no)
        else:
            go(y); go(no)
    go(root)
    return out
def fmtkey(k):
    if k[0]=='T': return 'T%d'%k[1]
    if k[0]=='F': return k[1]
    return '%s%s%s'%(k[0],k[1],k[2])
if __name__=='__main__':
    for v in ('160','162'):
        for hb in (0,2):
            dag,root=make('varleaves_%s_%d.pkl'%(v,hb))
            print(v,hb,'nodes',len(dag.nodes),'root',root)
