#!/bin/sh
# ARC retains a by-value 'id self' parameter of a plain C function on entry and releases it on exit: in a replacement of -dealloc that
# ends with the super / original dealloc, that release hits the freed object (build 406 crash, SpringBoard, y34 wrapper dealloc).
# Every C function used as a dealloc IMP must declare its receiver __unsafe_unretained.   usage: tools/lint_dealloc.sh [dir]
d=${1:-.}; n=0
for f in "$d"/*.x "$d"/*.m; do
  [ -f "$f" ] || continue
  grep -nE '^static +void +[A-Za-z0-9_]*[Dd]ealloc[A-Za-z0-9_]*\((id|[A-Za-z]+ *\*) +[a-z]+,' "$f" && n=$((n+1))
done
[ $n -eq 0 ] && echo "dealloc lint: ok" || echo "dealloc lint: receivers above lack __unsafe_unretained"
[ $n -eq 0 ]
