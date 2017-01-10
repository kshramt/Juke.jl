desc("do good stuff")
job(:default, [:a, :b])


desc("do a")
desc("and it invokes c")
job(:a, :c)


job(:c)


desc("bee")
job(:b)
