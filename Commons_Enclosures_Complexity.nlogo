extensions [ rnd ]

globals
[
  max-resource    ; maximum amount any patch can hold
  avgresource
  avgnorm
  avg-wealth
  max-wealth
  gini-index-reserve
  lorenz-points
  c-growers ; highlander with [cacao-grower? = true]
  t-growers ; highlander with [tobacco-grower = true]
]

breed [highlanders highlander]
; distance from market determines probability of growing commercial crops
breed [markets market]

patches-own
[
  resource-here      ; the current amount of resource on this patch
  max-resource-here  ; the maximum amount of resource this patch can hold
  cacao-crop? ; if true, owned by c-grower, & others can't go there.
  owner ; c-growers own cacao-crop patches. "Nobody" otherwise.
  initial-resource ; resource-here on set-up
]

highlanders-own
[
  wealth
  vision            ; how many patches ahead a highlander can see
  norm-min-resource ; minimum amount of resources on patch before agent will harvest
  copied-norm
  harvestedlevel
  cacao-grower? ; if true, patches used become private property, cacao crop.
  cacao-crops ; Number of cacao crop patches are acquired.
  cacao-profit ; wealth made per tick from cacao growing
  owned-patches ; a list of patches owned by cacao growers
  market-distance ; distance to market
  costpunished-c ; the loss per tick that punished cacao-grower suffers
  t-grower? ; if true, tobacco grower.
  trad-grower? ; highlanders growing only traditional crops
]

to setup
  clear-all
  set max-resource 50
  setup-patches
  setup-highlanders
  setup-markets
  reset-ticks
end


to setup-patches
  ask patches
  [ set resource-here 0
    set max-resource-here 0
    set cacao-crop? false
    set owner nobody
  ]
  ask patches with [ (random-float 100) <= percent-best-land ]
  [ set resource-here max-resource
    set max-resource-here resource-here
  ]
  repeat 5
  [ ask patches with [max-resource-here != 0]
    [ set resource-here max-resource-here
    ]
    diffuse resource-here 0.25
  ]
  ;; now diffuse all the patches values
  repeat 10
  [ diffuse resource-here 0.25
  ]
  ask patches
  [ set resource-here floor resource-here    ;; round resource levels to whole numbers
    set max-resource-here resource-here      ;; initial resource level is also maximum
    recolor-patch
    set initial-resource resource-here ; save initial resource for abandoned farm use
  ]
end

to recolor-patch
  set pcolor scale-color yellow resource-here 0 max-resource
end

to setup-markets
  set-default-shape markets "house"
  create-markets 1
  [ move-to one-of patches
    set size 2
    set color blue
  ]
end

to setup-highlanders
  set-default-shape highlanders "dot"
  create-highlanders num-people
  [ move-to one-of patches
    set size 2
    set color red
    ifelse imitate? [
      set norm-min-resource 0.5
    ][
      set norm-min-resource min-resource
    ]
    face one-of neighbors4
    set wealth 0
    set vision 1 + random max-vision
    set cacao-profit 0
    set cacao-grower? false ; initially no one is a cacao grower
    set t-grower? false ; initially no one is tobacco-grower
    set trad-grower? true ; initially all grow only traditional crops
    set market-distance max-one-of markets [ distance myself ]
    set costpunished-c 0
  ]
end

to go
  ;;========Set global variables========;;
  set max-wealth max [wealth] of highlanders
  let trad-growers highlanders with [ cacao-grower? = false and t-grower? = false]
  set c-growers highlanders with [ cacao-grower? = true ]
  set t-growers highlanders with [ t-grower? = true ]

    ;;========Patches Processes========;;
  ask patches
  [
    grow-resource
    recolor-patch
  ]
  ask patches with [cacao-crop? = true]
  [
    set resource-here resource-here - 1
    if resource-here < 0
    [
      set resource-here 0
    ]
  ]

  ;;========Initiate new tobacco-growers========;;
  ask trad-growers
  [
    set market-distance distance (one-of markets)
    if market-distance <= tobacco-initiation-radius and
      random 100 < probability-tob and tobacco? and
      ticks > 170
    [
      become-t-grower
    ]
  ]

  ;;========Initiate new cacao growers and farms========;;
  ask highlanders with [ cacao-grower? = false ]
  [
    set market-distance distance (one-of markets)
  ]
  if new-c-growers > count highlanders with [ cacao-grower? = false ]
  [
    set new-c-growers count highlanders with [ cacao-grower? = false ]
  ]
  ; the closer to market, the more likely to become c-grower
  if cacao? and ticks > 200
  [
    ask rnd:weighted-n-of new-c-growers highlanders with [ cacao-grower? = false ] [ 1 / (market-distance + 0.001)]
    [
      become-cacao-grower
    ]
  ]
  ; newly ACCUMULATED cacao-farms initiated
  ask c-growers
  [ ; necessary for rnd:weighted-n-of function, no neg wealths
    if wealth < 0
      [
        set wealth 0
      ]
  ]
  if accumulators > count c-growers
  [
    set accumulators count c-growers
  ]
  ask rnd:weighted-n-of accumulators c-growers [wealth] [ accumulate ]
  ask c-growers
  [
    color-cacao-farms
  ]

  ;;========Production (non-cacao-growers)========;
  ; choose direction holding most resource within the highlander's vision
  ask highlanders with [ cacao-grower? = false ] ; must be done together, prevents converging
  [
    turn-towards-resource
    fd 1
    let NO-CROP patches with [cacao-crop? = false]
    if any? NO-CROP
    ; if non-cacao-growers trapped by cacao farms, jump to NO-CROP
    [
      if cacao-crop? = true
      [
        move-to one-of NO-CROP
;        show word "i jumped b/c i was trapped by cacao farms" self
      ]
    ]
    harvest-traditional
  ]
  ;;========Production (cacao-growers)========;;
    if any? c-growers
  [
    ask c-growers
    [
      move-cacao-growers
      harvest-cacao
      harvest-traditional
    ]
  ]

  ;;========Decisions (non-cacao-growers)========;;
  ask highlanders with [ cacao-grower? = false ]
  [
    set wealth wealth * discount
    if punish-traditional?
    [
      monitor
    ]
    if imitate?
    [
      imitate
    ]
;    "if I"m doing poorly, then reset norm-min-resource to copy somebody else"
    if wealth < 0
    [ set wealth 0
      set norm-min-resource [norm-min-resource] of one-of highlanders with [ self != myself]
    ]
;    brightness increases with norm-min-resource
    if not t-grower?
    [
      set color 13 + (4 * norm-min-resource)
    ]
    if punish-c-growers? and random 100 < strength-of-c-punishment
    [
      punish-cacao-growers
    ]
  ]

    ;;========Decisions (t-growers)========;;

  ask t-growers
  [
    if norm-min-resource >= mean [norm-min-resource] of trad-growers
    [
      abandon-t-growing
    ]
  ]

    ;;========Decisions (c-growers)========;;
  if any? c-growers
  [
    ask c-growers
    [
      abandon-cacao
      set wealth wealth * discount
    ]
  ]

  ;;========Reset Globals for Plots, and tick========;;
  if ticks > 1000
  [
    set avgnorm avgnorm + 0.001 * mean [norm-min-resource] of highlanders
    set avg-wealth avg-wealth + 0.001 * mean [wealth] of highlanders
    set avgresource avgresource + 0.001 * mean [resource-here] of patches
  ]
  update-lorenz-and-gini
  tick
end

;Initiation of tobacco-growers, if within tobacco-initiation-radius of market
to become-t-grower
  ; run by trad-growers
  set t-grower? true
  ; they abuse resource norm a bit.
  set norm-min-resource norm-min-resource - How-much-t-growers-overharvest
  if norm-min-resource < 0
  [
    set norm-min-resource 0
  ]
  set color 124 + (4 * norm-min-resource)
end

to abandon-t-growing
  set color 13 + (4 * norm-min-resource)
  set t-grower? false
end

;; new cacao growers are picked randomly weighted by reciprocal of market distance.
to become-cacao-grower
  ;; run by rnd:weighted-n-of new-c-growers non-cacao-growers
  let available-patches patches with
   [ cacao-crop? = false and max-resource-here >= 1 ]
  if any? available-patches
  [
    set color blue
    set cacao-grower? true
    set t-grower? false ;
    set trad-grower? false
    ; try to move to non-cacao patch within radius 5, or increment search radius
    let radius-new-cfarm 5
    while [1 > count available-patches in-radius radius-new-cfarm ]
    [
     set radius-new-cfarm radius-new-cfarm + 1
    ]
    ; move to random non-cacao-crop patch within search radius
    move-to one-of available-patches in-radius radius-new-cfarm
  ]
  ; Decrement the EQUIVALENT OF slider (so slider is NOT changed for every case)
  let neighbor-patches-to-cacao extra-cacao-patches
  let available-neighbors
    neighbors with [cacao-crop? = false and max-resource-here >= 1]
  while [ neighbor-patches-to-cacao > count available-neighbors ]
  [ ; decrement if there's not enough new patches to turn into cacao crops
    set neighbor-patches-to-cacao neighbor-patches-to-cacao - 1
  ]
  ask n-of neighbor-patches-to-cacao available-neighbors
    [ ; turn neighbor-patches-to-cacao neighboring patches,
    ; and cacao-crop variable to "true" and mark who owns them.
    set cacao-crop? true
    set owner myself
    ]
  ask patch-here
  [
    set cacao-crop? true
    set owner myself
  ]
  set cacao-crops count patches with [owner = myself]
end

; if noncommercial-growers encounter c-growers getting too rich, they punish them
to punish-cacao-growers
  if wealth > costpunish and max-wealth > 0
    [
      let too-rich wealth * cacao-cheat-threshold
      let cacao-cheaters c-growers with [wealth > too-rich] in-radius radius
      let cheater-list [self] of cacao-cheaters
      if any? cacao-cheaters
      [
        set wealth wealth - count cacao-cheaters * costpunish
        ask cacao-cheaters
        [
          let former-wealth wealth
          set wealth wealth - wealth * percent-c-wealth-lost-to-punishment
          set costpunished-c former-wealth - wealth *
            percent-c-wealth-lost-to-punishment
        ]
      ]
    ]
end

;; cacao-growers accumulate more farm patches, according to wealth
to accumulate
  let available-patches patches with [cacao-crop? = false and max-resource-here >= 1]
  if any? available-patches
  [ ; try to get patches within radius 5, otherwise look further
    let radius-new-cfarm 5
        while [ count available-patches in-radius radius-new-cfarm < 1]
    [
      set radius-new-cfarm radius-new-cfarm + 1
    ]
    move-to one-of available-patches in-radius radius-new-cfarm
  ]
  let available-neighbors neighbors with
    [ cacao-crop? = false and max-resource-here >= 1 ]
  if any? available-neighbors
  [ ; substitute for extra-cacao-patches to not permanently change slider.
    let extra-cacao-patches-temp extra-cacao-patches
    while [extra-cacao-patches-temp > count available-neighbors ]
    [
      set extra-cacao-patches-temp extra-cacao-patches-temp - 1
    ]
    ask n-of extra-cacao-patches-temp available-neighbors
    [ set cacao-crop? true
      set owner myself
    ]
    ask patch-here
    [ set cacao-crop? true
      set owner myself
    ]
  ]
  set cacao-crops count patches with [ owner = myself ]
end

To move-cacao-growers
  if any? other patches with [ owner = myself ]
  [ move-to one-of patches with [ owner = myself ]
  ]
end

to tobaccogrower-actions
end

to turn-towards-resource
  ;; this is run by non-cacao-growers
  ; determine the direction which is most profitable in the surrounding patches
;  within the turtles' vision , excluding patches with [ cacao-crop? = true ]
  let available-patches neighbors4 with [ not cacao-crop? ]
  ifelse
  ( any? available-patches )
  [ ;; of those available, pick the best one.
    face max-one-of available-patches [ resources-ahead ]  ;; should this only consider non-crop patches?
  ]
  [ ;; all seem to be in use, so just pick a random direction
    set heading 90 * random 4
  ]
end

to-report resources-ahead
  ;; run by a neighbor patch that is available, with myself being the non-cacao-grower
  ;; we set up p-dx, p-dy, like dx and dy of a turtle
  ;; angle  p-dx  p-dy
  ;;    0     0     1
  ;;   90     1     0
  ;;  180     0    -1
  ;;  270    -1     0
  let p-dx pxcor - [ pxcor ] of myself
  let p-dy pycor - [ pycor ] of myself
  ;; build a set of patches in the line faced.
  ;; this automatically handles wrapped world, or un-wrapped world
  let visible-patches (patch-set n-values ([ vision ] of myself) [ dist -> patch (pxcor + p-dx * dist) (pycor + p-dy * dist) ])
  report sum [ resource-here ] of visible-patches
end

to grow-resource
  if max-resource-here > 0
  [
    set resource-here resource-here +
      regrowth-rate * resource-here * (1 - resource-here / max-resource-here)
  ]
end

;; each turtle harvests the resource on its patch.
to harvest-traditional
  set harvestedlevel 10 ; so only agents who actually harvested may get punished
  if resource-here >= 1 and resource-here >= (norm-min-resource * max-resource-here)
  [
    set harvestedlevel resource-here / max-resource-here
    set resource-here resource-here - 1
    set wealth wealth + 1
  ]
end

;; harvesting only cacao-growers do.
; Profit is calculated: crops * price - farm costs
; crops = product of the sum of each:
;   (max-resource-here of cacao farm patches *
;      (c-crop-coefficient + rnd normal, sd = half max))
; farm costs = product of the sum of each:
;   rnd normal (max-resource-here of cacao farm patches * c-crop-coefficient)
; sd =  (rnd normal (max-resource-here of cacao farm patches * c-crop-coefficient) / 2)
to harvest-cacao
  ; run by c-growers
  ; makes a list of the max-resource-here values of patches owned by cacao-growers
  let maxes [ max-resource-here ] of patches with [ owner = myself ]
  let c-harvest []
;; makes c-harvest a list of normally distributed numbers with a mean of the
;  max-resource-here value of each patch owned * "c-crop-coefficient",
;; and a standard deviation of half of that product:
  foreach maxes
  [
    x -> set c-harvest lput random-normal (x * c-crop-coefficient)
      ((x * c-crop-coefficient) / 2) c-harvest
  ]
  let harvest-total sum c-harvest ; total harvest of all cacao crop patches owned.
  let farm-cost []
  ;; makes farm-cost a list of normally distributed numbers with a mean of a
;  fraction of the max-resource-here values of owned patches,
;  and a standard deviation of a half that:
  foreach maxes
  [
    x -> set farm-cost lput random-normal
      (x * c-farm-cost) ((x * c-farm-cost) / 2) c-harvest
  ]
  let farm-costs-total sum farm-cost
  ; cacao-profit = amount harvested * price (slider) minus cost of farming.
  set cacao-profit harvest-total * cacao-price - farm-costs-total
  set wealth wealth + cacao-profit
end

; if cacao growing failing in comparison with what you you'd get with
; traditional harvest (+ 1), OR if you got punished for
; cacao growing and lost ~percent-c-wealth-lost-to-punishment of your
; wealth, then abandon cacao growing
to abandon-cacao
  if cacao-profit < 1 or costpunished-c > wealth * percent-c-wealth-lost-to-punishment +
    random-normal costpunished costpunished / 4
  [
    set cacao-grower? false
    set color 13 + (4 * norm-min-resource)
    ask patches with [ owner = myself ]
    [
      set owner nobody
      set cacao-crop? false
      set resource-here initial-resource / 2 ; abandoned have 1/2 initial resource
    ]
  ]
end

to color-cacao-farms
  ask patches with [ owner = myself ]
  [ set pcolor brown ]
end

to imitate
  set copied-norm norm-min-resource
  let other1 one-of other highlanders-here
  if other1 != nobody
  [
    let ratio 0
    if [wealth] of other1 > wealth
      [
        set copied-norm [norm-min-resource] of other1 + random-normal 0 stdeverror
        if copied-norm > 1 [set copied-norm 1]
        if copied-norm < 0 [set copied-norm 0]
      ]
    ]
  set norm-min-resource copied-norm
end

to monitor
  if wealth > costpunish
    [
      let threshold norm-min-resource
      let cheaters highlanders in-radius radius with [harvestedlevel < threshold]
      if cheaters != nobody
      [
        set wealth wealth - count cheaters * costpunish
        ask cheaters [set wealth wealth - costpunished]
      ]
    ]
end

; Lorenz curve and gini-index adapted from Wealth Distrubution model
to update-lorenz-and-gini
  let sorted-wealths sort [wealth] of highlanders
  let total-wealth sum sorted-wealths
  let wealth-sum-so-far 0
  let index 0
  set gini-index-reserve 0
  set lorenz-points []
  ;; now actually plot the Lorenz curve -- along the way, we also
  ;; calculate the Gini index.
  if total-wealth > 0
  [
    repeat num-people
    [
      set wealth-sum-so-far (wealth-sum-so-far + item index sorted-wealths)
      set lorenz-points lput ((wealth-sum-so-far / total-wealth) * 100) lorenz-points
      set index (index + 1)
      set gini-index-reserve
      gini-index-reserve +
      (index / num-people) -
      (wealth-sum-so-far / total-wealth)
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
680
10
1350
681
-1
-1
6.5545
1
10
1
1
1
0
1
1
1
-50
50
-50
50
1
1
1
ticks
30.0

BUTTON
0
117
55
150
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
54
117
109
150
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
252
524
420
557
max-vision
max-vision
1
15
10.0
1
1
NIL
HORIZONTAL

SLIDER
253
667
420
700
regrowth-rate
regrowth-rate
0
1
0.01
0.01
1
NIL
HORIZONTAL

SLIDER
252
489
420
522
num-people
num-people
0
1000
1000.0
1
1
NIL
HORIZONTAL

SLIDER
252
631
420
664
percent-best-land
percent-best-land
5
25
10.0
1
1
%
HORIZONTAL

PLOT
419
10
676
130
Resource
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [resource-here] of patches"

SLIDER
252
559
420
592
min-resource
min-resource
0
1
0.5
0.01
1
NIL
HORIZONTAL

SLIDER
252
595
420
628
discount
discount
0
1
0.95
0.01
1
NIL
HORIZONTAL

PLOT
422
255
678
412
mean and median wealth (all highlanders)
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"mean weath" 1.0 0 -16777216 true "" "plot mean [wealth] of highlanders"
"median wealth" 1.0 0 -5298144 true "" "plot median [wealth] of highlanders"
"pen-2" 1.0 0 -14070903 true "" "plot min [wealth] of highlanders"

SWITCH
253
703
358
736
imitate?
imitate?
0
1
-1000

SLIDER
253
314
419
347
stdeverror
stdeverror
0
0.1
0.01
0.01
1
NIL
HORIZONTAL

PLOT
420
133
676
253
Threshold
NIL
NIL
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [norm-min-resource] of highlanders"

SLIDER
253
350
419
383
costpunish
costpunish
0
1
0.01
0.01
1
NIL
HORIZONTAL

SLIDER
253
386
419
419
costpunished
costpunished
0
1
0.06
0.01
1
NIL
HORIZONTAL

SLIDER
253
422
419
455
radius
radius
0
10
10.0
1
1
NIL
HORIZONTAL

SWITCH
252
457
409
490
punish-traditional?
punish-traditional?
0
1
-1000

BUTTON
107
117
162
150
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
0
736
200
886
Lorenze Curve
Pop %
Wealth %
0.0
100.0
0.0
100.0
false
true
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot-pen-reset\nset-plot-pen-interval 100 / num-people\nplot 0\nforeach lorenz-points plot"
"pen-1" 100.0 0 -16777216 true "plot 0\nplot 100" ""

PLOT
203
737
403
887
Gini-Index v. Time
NIL
NIL
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -13345367 true "" "plot (gini-index-reserve / num-people) / 0.5"

SLIDER
2
422
156
455
cacao-price
cacao-price
0
1000
100.0
.1
1
NIL
HORIZONTAL

SLIDER
0
252
149
285
extra-cacao-patches
extra-cacao-patches
0
8
1.0
1
1
NIL
HORIZONTAL

SLIDER
0
44
148
77
new-c-growers
new-c-growers
0
100
1.0
1
1
NIL
HORIZONTAL

SLIDER
0
77
148
110
accumulators
accumulators
0
20
0.0
1
1
NIL
HORIZONTAL

SLIDER
1
352
155
385
c-crop-coefficient
c-crop-coefficient
0
100
1.0
.1
1
NIL
HORIZONTAL

SLIDER
1
387
156
420
c-farm-cost
c-farm-cost
0
10
5.0
.1
1
NIL
HORIZONTAL

SLIDER
0
285
213
318
cacao-cheat-threshold
cacao-cheat-threshold
0
1000000
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
1
318
251
351
percent-c-wealth-lost-to-punishment
percent-c-wealth-lost-to-punishment
0
1
1.0
.1
1
NIL
HORIZONTAL

SWITCH
178
11
314
44
punish-c-growers?
punish-c-growers?
1
1
-1000

SLIDER
2
456
194
489
strength-of-c-punishment
strength-of-c-punishment
0
100
100.0
1
1
NIL
HORIZONTAL

SLIDER
0
220
172
253
probability-tob
probability-tob
0
100
50.0
1
1
NIL
HORIZONTAL

SLIDER
0
187
175
220
tobacco-initiation-radius
tobacco-initiation-radius
0
50
5.0
1
1
NIL
HORIZONTAL

SWITCH
0
10
90
43
tobacco?
tobacco?
0
1
-1000

SLIDER
0
153
208
186
How-much-t-growers-overharvest
How-much-t-growers-overharvest
0
1
0.01
0.01
1
NIL
HORIZONTAL

SWITCH
90
10
180
43
cacao?
cacao?
0
1
-1000

PLOT
0
569
200
719
percent land privately owned
NIL
NIL
0.0
100.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot 100 * (count patches with [cacao-crop? = true]) / 10201"

PLOT
418
413
682
657
Enclosure Stats
ticks
percent initial resources private
0.0
10.0
0.0
100.0
true
true
"let total-initial-resources sum [initial-resource] of patches\nlet total-initial-res-privately-owned sum [initial-resource] of patches with [cacao-crop? = true]\nlet percent-private (sum [initial-resource] of patches with [cacao-crop? = true]) / (sum [initial-resource] of patches) * 100" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (sum [initial-resource] of patches with [cacao-crop? = true]) / (sum [initial-resource] of patches) * 100"

@#$#@#$#@
Commons and Commodification ABM Explained (Draft 8-4-22)

Background

The purpose of this model is to explore the dynamics of “self-governed commons” (Ostrom, 1990), where people have been able to use a common pool resource for multiple generations sustainably, and some of the forces at play when these commons come unraveled versus staying resilient. The focus comes from Tania Murray Li’s account of what happened with the Lauje highlanders of Sulawesi, in her book Land's End: Capitalist Relations on an Indigenous Frontier (Li, 2014).

The Lauje had a remarkable indigenous way of living that involved culturally regulated free access to forest lands for swidden agriculture, leaving fallow periods for recovery. Most of their productive activity was for direct use or gift-exchange. For the most part, everybody had what they needed, and they enjoyed an astonishing form of autonomy, where it was unthinkable that anyone would have to work for someone else for a wage. Their form of life managed to coexist for centuries, in contact with modern Indonesian society, up until 1990, when a cacao tree-planting boom, which they themselves initiated without coercion, disrupted their processes of collective action. Within only twenty years, a few had accumulated significant wealth, but most were destitute and forced to try to find wage work or sell crops through the markets on the coast, to survive. 

In game theoretic terms, the Lauje could be said to have achieved a non-tragic equilibrium of the n-person prisoner’s dilemma, with the high level of cooperation of their traditional system. Thus they avoided the "tragedy of the commons" (Hardin, 1968). And the high payoff of selling cacao can be seen as a fatal temptation to “cheat” on this egalitarian equilibrium, fatally disrupting their control of collective land ownership. 

In Li’s Marxian terms, capitalist relations had taken root, with social life now dominated by market exchange and commodity production. But it didn’t happen according to the classical Marxian narrative of “primitive accumulation” (Li, 2014, page 3). There was no land grab, no coercion driving this transition. 

This begs the question, is this transition to capitalist relations—reinterpreted here as the transition out of sophisticated cooperative equilibrium in a prisoner’s dilemma—an “inevitable” product of historical “progress”? Capitalism-boosters (Friedman, 1962) and many Marxist critics (Kautsky, 1988; Shanin, 2018) alike would answer affirmatively (see footnote 1). And yet we see that there is much variability in how successful different groups have been in resisting this fate, and for how long. And one can point to instances where the opposite dynamic has occurred. That is, there are times when groups of people break out of capitalist relations and form new self-governed commons. This is arguably the case with the “maroon ecologies” of escaped slave communities that persisted for many generations in Jamaica (Connell, 2020) and Brazil (Löwy, 2006), for example. 

Agent-based modeling affords us an opportunity to examine some of the different facets of these complex historical processes, both to make sense of what has happened, and to ask “what if” questions. What if the Lauje had had greater awareness of the threat the cacao boom posed to their way of life, for example? Might they have been able to resist the destruction of their remote mountainous self-governed commons, and for how many decades or centuries more? Is there any way that what has been lost could even be restored? 

What the Model Models

The model here is based on the “Governing the Commons” model in Marco Janssen’s book, Introduction to Agent-Based Modeling: with Applications to Social, Ecological, and Social-Ecological Systems (Janssen, 2020, page 214), which is in turn based upon the “Wealth Distribution” model by Uri Wilensky (1998), which in turn is built on Sugarscape (Epstein & Axtell, 1996). Janssen’s model gave a basic ABM of both Hardin’s tragedy of the commons (Hardin, 1968) and how non-tragic outcomes can be found through self-government, if cooperative norms are enforced. What the current model adds to that is an investigation of certain geographically specific, market-related threats to self-governed commons, and how these threats can be combatted. 

Although this model is loosely based on Li’s work on the Lauje (Li, 2014), there is no attempt at any great deal of realism or detail in representing that case. There is not enough reference data to do justice to that. Also, there is always a trade-off between realism, detail, and generality, when it comes to modeling (O’Sullivan & Perry, 2013, page 23). Instead, Li’s work and the case of the Lauje focalizes the dynamics of the model. But it must be seen as a rough approximation that can hopefully be useful in an abstract, heuristic way. There are, after all, many diverse cases of common property systems that have struggled to survive in the face of market pressures—a common theme in the literature of political ecology (Robbins, 2012, 45, 51).

The agents in the present model represent groups of highlanders. There is a grid of patches which is initialized upon starting each model run, which have different amounts of resources which regrow at a logistic rate. The agents move about the patches harvesting resources every “tick,” which represents a few years, the typical amount of time highlanders would stay in a clearing before letting it fallow (Li, 2014, 88). 

There are five important optional parameters that will be highlighted here: the switches labeled “cacao?”, “tobacco?”, “punish-traditional?”, “punish-c-growers?” and a slider, labeled “accumulators”.  Tobacco represents a crop that highlanders grew in recent centuries with an intermediate amount of production for market. Cacao-growing, which only started in the 1980s, was produced solely for market (footnote 2). 

When the model is run with the default parameters, and with all switches “off” and the “accumulators” slider set to zero, what we see is the “tragedy of the commons” (Hardin, 1968). The resource collapses fairly quickly and the wealth level of highlander groups plummets. By turning “punish-traditional?” on, we have enforcement of norms against overharvesting, such that agents who are found to be harvesting from a patch that is at less than half its maximum resource value are punished by others who can afford the cost of punishing. In this way, resource collapse can be averted in the model for the equivalent of millennia. This represents a self-governed commons (M. Janssen, 2020, 214; Ostrom, 1990).

The behavior of the model thus far is equivalent to what is shown by Janssen’s model (Janssen, 2020, page 214). If “tobacco?” is now switched on, those within a certain radius of a randomly placed “market” are tempted by higher payoffs to grow tobacco, which is represented in the model by overharvesting (footnote 3). Some of this mid-level commodification, when localized near the market, can coexist with a self-governed commons for the equivalent of many centuries. This matches what appears to have happened with Lauje highlanders (Li, 2014, 25). 

When “cacao?” is switched on, highlander groups are tempted by much higher payoffs to start growing cacao. The closer they are to the market, the higher the likelihood of them starting to grow it. When they do grow cacao, they take a group of patches as private property and cease to circulate or share their patches with others (footnote 4). With “accumulators” set to zero, we see equitable development of cacao farming. With that slider set higher, some accumulate many patches for cacao farms and other agents are left without any. The former scenario could be seen as a cacao-promoting NGO’s dream, and the latter scenario is more like realism in the case of the Lauje highlanders (Li, 2014, 139). 

Lastly, with “punish-c-growers?” turned on, agents can punish cacao-growers (footnote 5). To an extent, this can represent the “weapons of the weak” (Li, 2014, 155; Scott, 1985), such as gossip, theft, arson and slander, that highlanders did actually use against cacao-growers. In the model, however, we can turn up the dial on that punishment and adjust it until cacao-growing ceases, if we please. This can represent some of the “what if?” questions, alluded to earlier. What if the highlanders had had greater awareness of the threat the cacao boom posed to their way of life? Might they have been able to resist the destruction of their self-governed commons, and for how many decades or centuries more? With the model we can adjust this variously to represent alternate, hypothetical historical scenarios.

Footnotes
1. There is abundant evidence that Marx himself did not hold the belief in these fixed stages, at least in the last decade of his life (Shanin, 2018). But this has been largely ignored by Marxists.

2. Highlanders in fact never used cacao and did not understand its utility, besides being a commodity for sale (Li, 2014, 123).

3. The radius from the market, the rate at which agents are tempted to become tobacco-growers, and the amount they overharvest when doing so, can all be adjusted by sliders. 

4. The number of patches they start growing cacao on is adjustable—it is set by adding the number on the “extra-cacao-patches” slider to a default initial patch. 

5. The amount of punishment, how sensitive to punishment cacao-growers are, and the propensity to punish, are set by the “strength-of-c-punishment,” “percent-c-wealth-lost-to-punishment,” and “cacao-cheat-threshold” sliders, respectively. 
Bibliography

Connell, R. (2020). Maroon Ecology: Land, Sovereignty, and Environmental Justice. Journal of Latin American and Caribbean Anthropology, 25(2), 218–235. https://doi.org/10.1111/jlca.12496

Epstein, J. M., & Axtell, R. (1996). Growing Artificial Societies: Social Science from the Bottom Up. MIT Press.

Friedman, M. (1962). Capitalism and Freedom. University of Chicago Press.

Hardin, G. (1968). The tragedy of the commons: the population problem has no technical solution; it requires a fundamental extension in morality. Science1, 162(3859), 1243–1248.

Janssen, M. (2020). Introduction to Agent-Based Modeling: with Applications to Social, Ecological, and Social-Ecological Systems. Self-published.

Kautsky, K. (1988). The Agrarian Question. London: Zwan.

Li, T. M. (2014). Land’s End: Capitalist relations on an indigenous frontier. Duke University Press.

Löwy, M. (2006). La Commune des Palmares : Benjamin Péret et la révolte des esclaves du Brésil colonial. Tumultes, 27(2), 53. https://doi.org/10.3917/tumu.027.0053

O’Sullivan, D., & Perry, G. L. W. (2013). Spatial Simulation: Exploring Pattern and Process. Wiley-Blackwell.

Ostrom, E. (1990). Governing the commons: The evolution of institutions for collective action. Cambridge university press.

Robbins, P. (2012). Political Ecology: A Critical Introduction. Wiley-Blackwell.

Scott, J. C. (1985). Weapons of the Weak: Everyday Forms of Peasant Resistance. In Syria Studies (Vol. 7, Issue 1). Yale University Press.

Shanin, T. (Ed.). (2018). Late Marx and the Russian Road: Marx and the Peripheries of Capitalism. Verso.

Wilensky, U. (1998). Wealth Distribution model. Center for Connected Learning and Computer-Based Modeling, Northwestern Institute on Complex Systems, Northwestern University, Evanston, IL. http://ccl.northwestern.edu/netlogo/models/WealthDistribution
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2000"/>
    <metric>avgresource</metric>
    <metric>avgnorm</metric>
    <metric>avgwealth</metric>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="5"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <steppedValueSet variable="costpunished" first="0" step="0.02" last="0.1"/>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment2" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>mean [resource-here] of patches = 0.5 OR ticks &gt;= 3000</exitCondition>
    <metric>mean [resource-here] of patches</metric>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-cacao-growers">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <steppedValueSet variable="costpunished" first="0.01" step="0.02" last="0.1"/>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment3" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>mean [resource-here] of patches &lt; 0.6  OR ticks &gt;= 100</exitCondition>
    <metric>mean [resource-here] of patches</metric>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-cacao-growers">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <steppedValueSet variable="costpunished" first="0.01" step="0.02" last="0.1"/>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp9" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000"/>
    <metric>count highlanders with [ cacao-grower = true ]</metric>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-cacao-growers">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cost-punished-cacao">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish?">
      <value value="true"/>
    </enumeratedValueSet>
    <steppedValueSet variable="c-farm-cost" first="0" step="0.3" last="0.9"/>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="0"/>
      <value value="4"/>
      <value value="7"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="0"/>
      <value value="4"/>
      <value value="7"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <steppedValueSet variable="costpunish" first="0.1" step="0.11" last="0.12"/>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.03"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp10" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="10000"/>
    <metric>count highlanders with [ cacao-grower = true ]</metric>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-cacao-growers">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cost-punished-cacao">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="0"/>
      <value value="5"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="1"/>
      <value value="30"/>
      <value value="70"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="0"/>
      <value value="10"/>
      <value value="100"/>
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp11" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="10000"/>
    <metric>count highlanders with [ cacao-grower = true ]</metric>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-cacao-growers">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cost-punished-cacao">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="0"/>
      <value value="5"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="1"/>
      <value value="30"/>
      <value value="70"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="0.9"/>
      <value value="1.1"/>
      <value value="10"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp13" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="5000"/>
    <metric>count highlanders with [cacao-grower = true]</metric>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-cacao-growers">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cost-punished-c-coeff">
      <value value="0"/>
      <value value="1"/>
      <value value="0.5"/>
      <value value="0.7"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp14" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>mean [resource-here] of patches &lt;= 0.5</exitCondition>
    <metric>mean [resource-here] of patches</metric>
    <enumeratedValueSet variable="percent-c-wealth-lost-to-punishment">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.06"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strength-of-c-punishment">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-c-growers?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="probability-tob">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="10"/>
    </enumeratedValueSet>
    <steppedValueSet variable="How-much-t-growers-overharvest" first="0.01" step="0.01" last="0.1"/>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-traditional?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-c-growers">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco-initiation-radius">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp15" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>mean [resource-here] of patches &lt;= 0.5</exitCondition>
    <metric>mean [resource-here] of patches</metric>
    <enumeratedValueSet variable="percent-c-wealth-lost-to-punishment">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.06"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strength-of-c-punishment">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-c-growers?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="probability-tob">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="10"/>
    </enumeratedValueSet>
    <steppedValueSet variable="How-much-t-growers-overharvest" first="0" step="0.01" last="0.1"/>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-traditional?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-c-growers">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco-initiation-radius">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp16" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>mean [resource-here] of patches &lt;= 0.5</exitCondition>
    <metric>mean [resource-here] of patches</metric>
    <enumeratedValueSet variable="percent-c-wealth-lost-to-punishment">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.06"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strength-of-c-punishment">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-c-growers?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="probability-tob">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="How-much-t-growers-overharvest">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-traditional?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-c-growers">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco-initiation-radius">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp17" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>mean [resource-here] of patches &lt;= 0.5</exitCondition>
    <metric>mean [resource-here] of patches</metric>
    <enumeratedValueSet variable="percent-c-wealth-lost-to-punishment">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="imitate?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco-initiation-radius">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-cheat-threshold">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strength-of-c-punishment">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="extra-cacao-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-c-growers?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="probability-tob">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tobacco?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="percent-best-land">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-farm-cost">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="How-much-t-growers-overharvest">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-resource">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="c-crop-coefficient">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stdeverror">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao-price">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="punish-traditional?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="regrowth-rate">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunish">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cacao?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="radius">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="new-c-growers">
      <value value="0"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="accumulators">
      <value value="0"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-vision">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="costpunished">
      <value value="0.06"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="discount">
      <value value="0.95"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="1000"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 30 225
Line -7500403 true 150 150 270 225
@#$#@#$#@
0
@#$#@#$#@
