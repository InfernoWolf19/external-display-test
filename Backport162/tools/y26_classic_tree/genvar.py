import sys, pickle
from emu import *
ver=sys.argv[1]; hb=int(sys.argv[2])
fn=load(ver); env={'dc':2,'hb':hb,'bounds':None}
leaves=explore_under(fn, env, {})
print(ver,'hb',hb,'leaves',len(leaves))
pickle.dump(leaves, open('varleaves_%s_%d.pkl'%(ver,hb),'wb'))
