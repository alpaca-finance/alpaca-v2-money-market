# Deployment seqeunce

- deploy proxy admin
- deploy miniFL implementation
- deploy miniFL proxy
- deploy moneyMarket facets
- deploy moneyMarket diamond
- diamond cut on moneyMarket
- whitelist moneyMarket on miniFL to allow openMarket
- (optional) deploy nativeRelayer
- set ibToken, debtToken implementation
- openMarket for wNativeToken
- deploy accountManager
- (optional) deploy reader
- (optional) deploy repurchaser contract
- allow accountManager on moneyMarket
- whitelist accountManager on miniFL to allow deposit and withdraw

## Dependencies

### MiniFL

- proxy admin
- implementation

### MoneyMarket

- all facets implementation
- diamond cut

#### openMarket

- miniFL whitelisted mm
- ibToken, debtToken implementation set

### Reader

- moneyMarket

### AccountManager

- wNativeToken
- nativeRelayer
- moneyMarket
- opened market for wNativeToken
