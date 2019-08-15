//
//  BRCryptoWalletTests.swift
//  BRCryptoTests
//
//  Created by Ed Gamble on 1/11/19.
//  Copyright © 2019 Breadwallet AG. All rights reserved.
//
//  See the LICENSE file at the project root for license information.
//  See the CONTRIBUTORS file at the project root for a list of contributors.
//

import XCTest
@testable import BRCrypto

class BRCryptoWalletTests: BRCryptoSystemBaseTests {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
    }

    func testWalletBTC() {
        isMainnet = false
        currencyCodesNeeded = ["btc"]
        modeMap = ["btc":WalletManagerMode.api_only]
        prepareAccount (AccountSpecification (dict: [
            "identifier": "ginger",
            "paperKey":   "ginger settle marine tissue robot crane night number ramp coast roast critic",
            "timestamp":  "2018-01-01",
            "network":    (isMainnet ? "mainnet" : "testnet")
            ]))
        prepareSystem ()

        let walletManagerDisconnectExpectation = XCTestExpectation (description: "Wallet Manager Disconnect")
        listener.managerHandlers += [
            { (system: System, manager:WalletManager, event: WalletManagerEvent) in
                if case let .changed(_, newState) = event, case .disconnected = newState {
                    walletManagerDisconnectExpectation.fulfill()
                }
            }]

        let network: Network! = system.networks.first { "btc" == $0.currency.code && isMainnet == $0.isMainnet }
        XCTAssertNotNil (network)

        let manager: WalletManager! = system.managers.first { $0.network == network }
        XCTAssertNotNil (manager)

        let wallet = manager.primaryWallet
        XCTAssertNotNil(wallet)

        XCTAssertTrue  (system === wallet.system)
        XCTAssertEqual (manager, wallet.manager)
        XCTAssertEqual (network.currency, wallet.currency)
        XCTAssertEqual (wallet.unit, manager.unit)
        XCTAssertEqual (wallet.unit,       network.defaultUnitFor(currency: network.currency))
        XCTAssertEqual (wallet.unitForFee, network.defaultUnitFor(currency: network.currency))
        XCTAssertEqual (wallet.balance, Amount.create(integer: 0, unit: wallet.unit))
        XCTAssertEqual (wallet.state, WalletState.created)
        XCTAssertEqual (wallet.target, wallet.targetForScheme(manager.addressScheme))
        XCTAssertEqual (wallet, wallet)

        let feeBasisPricePerCostFactor = Amount.create (integer: 5000, unit: network.baseUnitFor(currency: network.currency)!)
        let feeBasisCostFactor = 1.0
        let feeBasis: TransferFeeBasis! =
            wallet.createTransferFeeBasis (pricePerCostFactor: feeBasisPricePerCostFactor,
                                           costFactor: feeBasisCostFactor)
        XCTAssertNotNil(feeBasis)
        XCTAssertEqual (feeBasis.currency, wallet.unitForFee.currency)
        XCTAssertEqual (feeBasis.pricePerCostFactor, feeBasisPricePerCostFactor)
        XCTAssertEqual (feeBasis.costFactor, feeBasisCostFactor)

        // No existing transfers
        XCTAssertTrue (wallet.transfers.isEmpty)

        // Create a target address THAT IS NOT in our wallet.
        let transferTargetAddressString = (isMainnet
            ? "1Cw9Un8ZorSDKSgUP82mbyrm5KNPLkLhts"   // https://live.blockcypher.com/btc/tx/a0d33c452353148fa5012a6c5065e875fd495ba9ae4acc45c96e4307d4e25103/
            : "2Mv9Fybn9ZAjdrT6LsvVALMNEqLgULy9D6Q") // https://live.blockcypher.com/btc-testnet/tx/241e78244a3d78bb55f46ea69c62a13985afba9021908516dd3d05f6e77ca62c/
        let transferTargetAddress: Address! = Address.create (string: transferTargetAddressString,
                                                              network: network)
        XCTAssertNotNil (transferTargetAddress)

        // With no existing transfers, cannot create a transfer (no BTC UTXOs)
        let transferBaseUnit = network.baseUnitFor(currency: network.currency)!
        let transferAmount = Amount.create (integer: 40000, unit: transferBaseUnit)
        var transfer: Transfer! = wallet.createTransfer (target: transferTargetAddress,
                                                         amount: transferAmount,
                                                         estimatedFeeBasis: feeBasis)
        XCTAssertNil(transfer)

        // Connect and wait for a number of transfers
        listener.transferCount = 10
        manager.connect()
        wait (for: [listener.transferExpectation], timeout: 70)

        // Try again
        transfer = wallet.createTransfer (target: transferTargetAddress,
                                          amount: transferAmount,
                                          estimatedFeeBasis: feeBasis)
        XCTAssertNotNil(transfer)
        XCTAssertEqual (transfer.wallet,  wallet)
        XCTAssertEqual (transfer.manager, manager)
        XCTAssertNotNil(transfer.estimatedFeeBasis)
        // the transfer's estimatedFeeBasis is the original feeBasis but w/ a correct cost factor
        XCTAssertNotEqual (transfer.estimatedFeeBasis!.fee, feeBasis.fee)
        XCTAssertNotEqual (transfer.fee, feeBasis.fee)
        XCTAssertEqual (transfer.target, transferTargetAddress)
        XCTAssertEqual (transfer.unit, wallet.unit)
        XCTAssertEqual (transfer.amount, transferAmount)
        // We sent `transferAmount` -> directed amount is negative.
        XCTAssertEqual (transfer.amountDirected, transferAmount.negate)

        XCTAssertNil   (transfer.confirmedFeeBasis)
        XCTAssertNil   (transfer.confirmation)
        XCTAssertNil   (transfer.confirmations)
        XCTAssertNil   (transfer.confirmationsAt(blockHeight: 10))

        XCTAssertNil   (transfer.hash)
        if case .created = transfer.state {} else { XCTAssertTrue (false ) }
        XCTAssertEqual (transfer.direction, TransferDirection.sent)

        // Estiamte the fee
        let feeEstimateExpectation = XCTestExpectation (description: "FeeEstimate")
        var feeEstimateResult: Result<TransferFeeBasis, Wallet.FeeEstimationError>!
        wallet.estimateFee (target: transferTargetAddress,
                            amount: transferAmount,
                            fee: network.minimumFee) { (res: Result<TransferFeeBasis, Wallet.FeeEstimationError>) in
                                feeEstimateResult = res
                                feeEstimateExpectation.fulfill()
        }
        wait (for: [feeEstimateExpectation], timeout: 10)
        XCTAssertNotNil (feeEstimateResult)
        if case .success = feeEstimateResult! {} else { XCTAssertTrue(false) }

        manager.disconnect()
        wait (for: [walletManagerDisconnectExpectation], timeout: 5)

        // Events

        XCTAssertTrue (listener.checkSystemEvents(
            [EventMatcher (event: SystemEvent.created),
             EventMatcher (event: SystemEvent.networkAdded(network: network), strict: true, scan: true),
             EventMatcher (event: SystemEvent.managerAdded(manager: manager), strict: true, scan: true)
            ]))

        XCTAssertTrue (listener.checkManagerEvents(
            [EventMatcher (event: WalletManagerEvent.created),
             EventMatcher (event: WalletManagerEvent.walletAdded(wallet: wallet)),
             EventMatcher (event: WalletManagerEvent.changed(oldState: WalletManagerState.created,   newState: WalletManagerState.connected)),
             EventMatcher (event: WalletManagerEvent.syncStarted),
             EventMatcher (event: WalletManagerEvent.changed(oldState: WalletManagerState.connected, newState: WalletManagerState.syncing)),
             EventMatcher (event: WalletManagerEvent.syncProgress(percentComplete: 0), strict: false),
             EventMatcher (event: WalletManagerEvent.walletChanged(wallet: wallet), strict: true, scan: true),
             EventMatcher (event: WalletManagerEvent.syncEnded(error: nil), strict: false, scan: true),
             EventMatcher (event: WalletManagerEvent.changed(oldState: WalletManagerState.syncing, newState: WalletManagerState.connected)),
             EventMatcher (event: WalletManagerEvent.changed(oldState: WalletManagerState.connected, newState: WalletManagerState.disconnected))
            ]))

        XCTAssertTrue (listener.checkWalletEvents(
            [EventMatcher (event: WalletEvent.created),
             EventMatcher (event: WalletEvent.transferAdded(transfer: transfer), strict: true, scan: true),
             EventMatcher (event: WalletEvent.balanceUpdated(amount: wallet.balance), strict: true, scan: true)
            ]))
    }

    func testWalletETH() {
        isMainnet = false
        currencyCodesNeeded = ["eth"]
        modeMap = ["eth":WalletManagerMode.api_only]
        prepareAccount (AccountSpecification (dict: [
            "identifier": "ginger",
            "paperKey":   "ginger settle marine tissue robot crane night number ramp coast roast critic",
            "timestamp":  "2018-01-01",
            "network":    (isMainnet ? "mainnet" : "testnet")
            ]))
        let listener = CryptoTestSystemListener (currencyCodesNeeded: currencyCodesNeeded,
                                                 isMainnet: isMainnet,
                                                 modeMap: modeMap)

        // Connect and wait for a number of transfers
        var walletCount: Int = 2
        let walletExpectation = XCTestExpectation (description: "Wallet")
        listener.managerHandlers += [
            { (system: System, manager: WalletManager, event: WalletManagerEvent) -> Void in
                switch event {
                case .walletAdded:
                    walletCount -= 1
                    if 0 == walletCount {
                        walletExpectation.fulfill()
                    }
                default: break
                }
            }]

        prepareSystem(listener: listener)

        let network: Network! = system.networks.first { "eth" == $0.currency.code && isMainnet == $0.isMainnet }
        XCTAssertNotNil (network)

        let manager: WalletManager! = system.managers.first { $0.network == network }
        XCTAssertNotNil (manager)

        wait (for: [walletExpectation ], timeout: 10)

        XCTAssertFalse (manager.wallets.isEmpty)
        XCTAssertTrue  (manager.wallets.count >= 2)
        let w0 = manager.wallets[0]
        let w1 = manager.wallets[1]

        XCTAssertEqual    (w0, w0)
        XCTAssertNotEqual (w0, w1)

        XCTAssertEqual ("eth", w0.name)
        XCTAssertEqual ("brd", w1.name)

        let walletETH = manager.primaryWallet
        XCTAssertNotNil(walletETH)
        let walletBRD = (manager.wallets[0] == manager.primaryWallet ? manager.wallets[1] : manager.wallets[0])
        XCTAssertNotNil(walletBRD)

        XCTAssertTrue (listener.checkSystemEvents(
            [EventMatcher (event: SystemEvent.created),
             EventMatcher (event: SystemEvent.networkAdded(network: network), strict: true, scan: true),
             EventMatcher (event: SystemEvent.managerAdded(manager: manager), strict: true, scan: true)
            ]))

        XCTAssertTrue (listener.checkManagerEvents(
            [WalletManagerEvent.created,
             WalletManagerEvent.walletAdded(wallet: walletETH),
             WalletManagerEvent.walletAdded(wallet: walletBRD)],
            strict: true))

        XCTAssertTrue (listener.checkWalletEvents(
            [WalletEvent.created,
             WalletEvent.created],
            strict: true))

        XCTAssertTrue (listener.checkTransferEvents(
            [],
            strict: true))

        XCTAssertTrue  (system === walletETH.system)
        XCTAssertEqual (manager, walletETH.manager)
        XCTAssertEqual (network.currency, walletETH.currency)
        XCTAssertEqual (walletETH.unit, manager.unit)
        XCTAssertEqual (walletETH.unit,       network.defaultUnitFor(currency: network.currency))
        XCTAssertEqual (walletETH.unitForFee, network.defaultUnitFor(currency: network.currency))
        XCTAssertEqual (walletETH.balance, Amount.create(integer: 0, unit: walletETH.unit))
        XCTAssertEqual (walletETH.state, WalletState.created)
        XCTAssertEqual (walletETH.target, walletETH.targetForScheme(manager.addressScheme))
        XCTAssertEqual (walletETH, walletETH)


        XCTAssertTrue  (system === walletBRD.system)
        XCTAssertEqual (manager, walletBRD.manager)
        XCTAssertNotEqual (network.currency, walletBRD.currency)
        XCTAssertNotEqual (walletBRD.unit, manager.unit)
        XCTAssertNotEqual (walletBRD.unit,       network.defaultUnitFor(currency: network.currency))
        XCTAssertEqual (walletBRD.unitForFee, network.defaultUnitFor(currency: network.currency))
        XCTAssertEqual (walletBRD.balance, Amount.create(integer: 0, unit: walletBRD.unit))
        XCTAssertEqual (walletBRD.state, WalletState.created)
        XCTAssertEqual (walletBRD.target, walletBRD.targetForScheme(manager.addressScheme))

    }
}
