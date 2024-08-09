The only edge case that broke things was if you were to move data from like users__1 with store key 1 to store key 2
and you had descendant data like users__1__friends__1 that referenced store 1, because now despite it still wanting to go into store 1, it gets moved to store key 2.

To get around this, how about you only have two groups, the docs that asked to be in this store explicitly and the docs that got rolled up into this store.

Docs that get rolled up into the store should just move over. Docs that explicitly asked to be in this store should stay.