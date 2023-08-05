import { Token, ValidatorCollection } from "../typechain-types";
import { Amount } from "./helper/Amount";

import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";

import assert from "assert";
import chai, { expect } from "chai";
import { solidity } from "ethereum-waffle";

import * as hre from "hardhat";

chai.use(solidity);

describe("Test for LinkCollection", () => {
    const provider = hre.waffle.provider;
    const [deployer, validator1, validator2, validator3, user1] = provider.getWallets();

    const validators = [validator1, validator2, validator3];
    let contract: ValidatorCollection;
    let tokenContract: Token;

    const amount = Amount.make(50000, 18);
    const halfAmount = Amount.make(25000, 18);

    before(async () => {
        const tokenFactory = await hre.ethers.getContractFactory("Token");
        tokenContract = (await tokenFactory.connect(deployer).deploy("Sample", "SAM")) as Token;
        await tokenContract.deployed();
        await tokenContract.deployTransaction.wait();
        for (const elem of validators) {
            await tokenContract.connect(deployer).transfer(elem.address, amount.value);
        }

        const factory = await hre.ethers.getContractFactory("ValidatorCollection");
        contract = (await factory.connect(deployer).deploy(
            tokenContract.address,
            validators.map((m) => m.address)
        )) as ValidatorCollection;
        await contract.deployed();
        await contract.deployTransaction.wait();
    });

    it("Check validator", async () => {
        let item = await contract.validators(validator1.address);
        assert.deepStrictEqual(item.validator, validator1.address);
        assert.deepStrictEqual(item.status, 2);

        item = await contract.validators(validator2.address);
        assert.deepStrictEqual(item.validator, validator2.address);
        assert.deepStrictEqual(item.status, 2);

        item = await contract.validators(validator3.address);
        assert.deepStrictEqual(item.validator, validator3.address);
        assert.deepStrictEqual(item.status, 2);
    });

    it("Deposit not validator", async () => {
        await tokenContract.connect(deployer).approve(contract.address, amount.value);
        await expect(contract.connect(deployer).deposit(amount.value)).to.be.revertedWith("Not validator");
    });

    it("Deposit not allowed", async () => {
        await expect(contract.connect(validators[0]).deposit(amount.value)).to.be.revertedWith("Not allowed deposit");
    });

    it("Deposit 25,000", async () => {
        for (const elem of validators) {
            await tokenContract.connect(elem).approve(contract.address, halfAmount.value);
            await expect(contract.connect(elem).deposit(halfAmount.value))
                .to.emit(contract, "Deposited")
                .withArgs(elem.address, halfAmount.value, halfAmount.value);
            let item = await contract.validators(elem.address);
            assert.deepStrictEqual(item.validator, elem.address);
            assert.deepStrictEqual(item.status, 2);
            assert.deepStrictEqual(item.balance, halfAmount.value);
        }
    });

    it("Deposit 50,000", async () => {
        for (const elem of validators) {
            await tokenContract.connect(elem).approve(contract.address, halfAmount.value);
            await expect(contract.connect(elem).deposit(halfAmount.value))
                .to.emit(contract, "Deposited")
                .withArgs(elem.address, halfAmount.value, amount.value);
            let item = await contract.validators(elem.address);
            assert.deepStrictEqual(item.validator, elem.address);
            assert.deepStrictEqual(item.status, 1);
            assert.deepStrictEqual(item.balance, amount.value);
        }
    });

    it("Request participation - already validator", async () => {
        await tokenContract.connect(deployer).transfer(validator1.address, amount.value);
        await tokenContract.connect(validator1).approve(contract.address, amount.value);
        await expect(contract.connect(validator1).requestRegistration()).to.be.revertedWith("Already validator");
    });

    it("Request participation - not allowed deposit", async () => {
        await tokenContract.connect(user1).approve(contract.address, amount.value);
        await expect(contract.connect(user1).requestRegistration()).to.be.revertedWith(
            "ERC20: transfer amount exceeds balance"
        );
    });

    it("Request participation", async () => {
        await tokenContract.connect(deployer).transfer(user1.address, amount.value);
        await tokenContract.connect(user1).approve(contract.address, amount.value);
        await expect(contract.connect(user1).requestRegistration())
            .to.emit(contract, "RequestedRegistration")
            .withArgs(user1.address);
        let item = await contract.validators(user1.address);
        assert.deepStrictEqual(item.validator, user1.address);
        assert.deepStrictEqual(item.status, 1);
        assert.deepStrictEqual(item.balance, amount.value);
    });
});