### Run code locally and generate rubocop report

```
$ git clone git@github.com:petrokoriakin/product_service.git
$ cd product_service/
$ bundle

# run specs to generate coverage report and make sure things are working
$ spec spec/models/sku_spec.rb

# run rubocop static code analyzer
$ rubocop
```