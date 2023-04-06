# Lending Protocol

A Solidity smart contract that implements the basic lending protocol.

## Pre Requisites
NodeJS version v16.14.0

## Quick start

Installing dependencies:

```sh
yarn install
```

## To deploy the contract on local network
```sh
yarn run deploy:hardhat
```

## To deploy the contract on goerli network

please add .env file to update the variables mentioned in .env.example file

```sh 
yarn run deploy:goerli
```

## To run the test cases
```sh
yarn run test
```

## Contract deployed on goerli network

https://goerli.etherscan.io/address/0xFBFC7Bc5B52f19643150ABA18265C993c3c41F4E#code

## Brief description of the solution
To start the lending-borrowing pool we have to add the token that should be supported for lending and borrowing.

## smart contract configuration

1. Add token by calling the following method: 

```sh
function addSupportedToken(address token, address priceFeed) external;
```

2. Supply the asset in the pool by calling the following method:

```sh
function supply(address token, uint256 amount) external;
```
only supported tokens can be supplied in the pool.
token should be approved before calling the supply method. 


3. Borrow collateral from the pool by calling the following method:

```sh
function borrow(address token, uint256 amount) external;
```
only supported tokens can be borrowed from the pool.
pool must have enough balance to borrow the amount.

4. To Repay the borrowed amount call the following method:

```sh
function repay(address token, uint256 amount) external;
```
to repay borrow amount, user must have enough balance in his account, and it should be approved to the pool contract.

5. To withdraw the asset from the pool call the following method:

```sh
function withdraw(address token, uint256 amount) external;
```
withdraw collateral supplied by the lender from the contract.

## getter methods are descibed in the natspec code comments format.


## Formula to calculate the interest rate

```

Interest rate for the supplied and borrow amount is calculated using the following formula:

interestRate = (timePassed * borrowAmount * stableRate)
interestRate is total interest rate for the supplied and borrow amount. 

```









