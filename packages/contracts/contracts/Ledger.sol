// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "del-osx-artifacts/contracts/LinkCollection.sol";
import "./ValidatorCollection.sol";
import "./TokenPrice.sol";
import "./FranchiseeCollection.sol";

/// @notice 마일리지와 토큰의 원장
contract Ledger {
    /// @notice Hash value of a blank string
    bytes32 public constant NULL = 0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;
    mapping(bytes32 => uint256) private mileageLedger;
    mapping(bytes32 => uint256) private tokenLedger;
    mapping(address => uint256) private nonce;

    struct PurchaseData {
        string purchaseId;
        uint256 timestamp;
        uint256 amount;
        bytes32 email;
        string franchiseeId;
        uint32 method;
    }

    mapping(string => PurchaseData) private purchases;
    string[] private purchaseIds;

    bytes32 public foundationAccount;
    address public tokenAddress;
    address public validatorAddress;
    address public linkCollectionAddress;
    address public tokenPriceAddress;
    address public franchiseeCollectionAddress;

    IERC20 private token;
    ValidatorCollection private validatorCollection;
    LinkCollection private linkCollection;
    TokenPrice private tokenPrice;
    FranchiseeCollection private franchiseeCollection;

    /// @notice 검증자가 추가될 때 발생되는 이벤트
    event SavedPurchase(
        string purchaseId,
        uint256 timestamp,
        uint256 amount,
        bytes32 email,
        string franchiseeId,
        uint32 method
    );
    /// @notice 마일리지가 지급될 때 발생되는 이벤트
    event ProvidedMileage(
        bytes32 email,
        uint256 providedAmountMileage,
        uint256 value,
        uint256 balanceMileage,
        string purchaseId
    );
    /// @notice 마일리지가 정산될 때 발생되는 이벤트
    event ProvidedMileageToFranchisee(
        bytes32 email,
        uint256 providedAmountMileage,
        uint256 value,
        uint256 balanceMileage,
        string franchiseeId
    );
    /// @notice 토큰이 지급될 때 발생되는 이벤트
    event ProvidedToken(
        bytes32 email,
        uint256 providedAmountToken,
        uint256 value,
        uint256 balanceToken,
        string purchaseId
    );
    /// @notice 마일리지로 지불을 완료했을 때 발생하는 이벤트
    event PaidMileage(
        bytes32 email,
        uint256 paidAmountMileage,
        uint256 value,
        uint256 balanceMileage,
        string purchaseId
    );
    /// @notice 토큰으로 지불을 완료했을 때 발생하는 이벤트
    event PaidToken(bytes32 email, uint256 paidAmountToken, uint256 value, uint256 balanceToken, string purchaseId);
    /// @notice 토큰을 예치했을 때 발생하는 이벤트
    event Deposited(bytes32 email, uint256 depositAmount, uint256 value, uint256 balanceToken, address account);
    /// @notice 토큰을 인출했을 때 발생하는 이벤트
    event Withdrawn(bytes32 email, uint256 withdrawAmount, uint256 value, uint256 balanceToken, address account);
    /// @notice 마일리지를 토큰으로 교환했을 때 발생하는 이벤트
    event ExchangedMileageToToken(
        bytes32 email,
        uint256 amountMileage,
        uint256 amountToken,
        uint256 balanceMileage,
        uint256 balanceToken
    );
    /// @notice 토큰을 마일리지로 교환했을 때 발생하는 이벤트
    event ExchangedTokenToMileage(
        bytes32 email,
        uint256 amountMileage,
        uint256 amountToken,
        uint256 balanceMileage,
        uint256 balanceToken
    );

    /// @notice 생성자
    /// @param _foundationAccount 재단의 계정
    /// @param _tokenAddress 토큰 컨트랙트의 주소
    /// @param _validatorAddress 검증자 컬랙션 컨트랙트의 주소
    /// @param _linkCollectionAddress 이메일-지갑주소 링크 컨트랙트의 주소
    /// @param _tokenPriceAddress 토큰가격을 제공하는 컨트랙트의 주소
    /// @param _franchiseeCollectionAddress 가맹점 컬랙션 컨트랙트의 주소
    constructor(
        bytes32 _foundationAccount,
        address _tokenAddress,
        address _validatorAddress,
        address _linkCollectionAddress,
        address _tokenPriceAddress,
        address _franchiseeCollectionAddress
    ) {
        foundationAccount = _foundationAccount;
        tokenAddress = _tokenAddress;
        validatorAddress = _validatorAddress;
        linkCollectionAddress = _linkCollectionAddress;
        tokenPriceAddress = _tokenPriceAddress;
        franchiseeCollectionAddress = _franchiseeCollectionAddress;

        token = IERC20(_tokenAddress);
        validatorCollection = ValidatorCollection(_validatorAddress);
        linkCollection = LinkCollection(_linkCollectionAddress);
        tokenPrice = TokenPrice(_tokenPriceAddress);
        franchiseeCollection = FranchiseeCollection(_franchiseeCollectionAddress);
    }

    modifier onlyValidator(address _account) {
        bool isValidator = false;
        for (uint256 i = 0; i < validatorCollection.activeItemsLength(); ++i) {
            if (_account == validatorCollection.activeItemOf(i)) {
                isValidator = true;
                break;
            }
        }
        require(isValidator, "Not validator");
        _;
    }

    /// @notice 구매내역을 저장합니다.
    /// @dev 이것은 검증자들에 의해 호출되어야 합니다.
    /// @param _purchaseId 구매 아이디
    /// @param _timestamp 구매 시간
    /// @param _amount 구매 금액
    /// @param _email 구매한 사용자의 이메일 해시
    /// @param _franchiseeId 구매한 가맹점 아이디
    function savePurchase(
        string memory _purchaseId,
        uint256 _timestamp,
        uint256 _amount,
        bytes32 _email,
        string memory _franchiseeId,
        uint32 _method
    ) public onlyValidator(msg.sender) {
        PurchaseData memory data = PurchaseData({
            purchaseId: _purchaseId,
            timestamp: _timestamp,
            amount: _amount,
            email: _email,
            franchiseeId: _franchiseeId,
            method: _method
        });
        purchaseIds.push(_purchaseId);
        purchases[_purchaseId] = data;

        if ((_method == 0) && (_email != NULL)) {
            uint256 mileage = _amount / 100;
            address account = linkCollection.toAddress(_email);
            if (account == address(0x00)) {
                provideMileage(_email, mileage, _purchaseId);
            } else {
                provideToken(_email, mileage, _purchaseId);
            }
            franchiseeCollection.addProvidedMileage(_franchiseeId, mileage, _purchaseId);
        }
        emit SavedPurchase(_purchaseId, _timestamp, _amount, _email, _franchiseeId, _method);
    }

    /// @notice 마일리지를 지급합니다.
    /// @dev 구매 데이터를 확인한 후 호출됩니다.
    /// @param _email 이메일 해시
    /// @param _amount 지급할 마일리지
    function provideMileage(bytes32 _email, uint256 _amount, string memory _purchaseId) internal {
        mileageLedger[_email] += _amount;
        emit ProvidedMileage(_email, _amount, _amount, mileageLedger[_email], _purchaseId);
    }

    /// @notice 토큰을 지급합니다.
    /// @dev 구매 데이터를 확인한 후 호출됩니다.
    /// @param _email 이메일 해시
    /// @param _amount 지급할 토큰
    function provideToken(bytes32 _email, uint256 _amount, string memory _purchaseId) internal {
        uint256 amountToken = convertMileageToToken(_amount);

        require(tokenLedger[foundationAccount] >= amountToken, "Insufficient foundation balance");
        tokenLedger[_email] += amountToken;
        tokenLedger[foundationAccount] -= amountToken;

        emit ProvidedToken(_email, amountToken, _amount, tokenLedger[_email], _purchaseId);
    }

    /// @notice 마일리지를 구매에 사용하는 함수
    /// @dev 중계서버를 통해서 호출됩니다.
    /// @param _purchaseId 구매 아이디
    /// @param _amount 구매 금액
    /// @param _email 구매한 사용자의 이메일 해시
    /// @param _franchiseeId 구매한 가맹점 아이디
    /// @param _signer 구매자의 주소
    /// @param _signature 서명
    function payMileage(
        string memory _purchaseId,
        uint256 _amount,
        bytes32 _email,
        string memory _franchiseeId,
        address _signer,
        bytes calldata _signature
    ) public {
        bytes32 dataHash = keccak256(abi.encode(_purchaseId, _amount, _email, _franchiseeId, _signer, nonce[_signer]));
        require(ECDSA.recover(ECDSA.toEthSignedMessageHash(dataHash), _signature) == _signer, "Invalid signature");
        address userAddress = linkCollection.toAddress(_email);
        require(userAddress != address(0x00), "Unregistered email-address");
        require(userAddress == _signer, "Invalid address");
        require(mileageLedger[_email] >= _amount, "Insufficient balance");

        mileageLedger[_email] -= _amount;
        franchiseeCollection.addUsedMileage(_franchiseeId, _amount, _purchaseId);

        uint256 clearAmount = franchiseeCollection.getClearMileage(_franchiseeId);
        if (clearAmount > 0) {
            franchiseeCollection.addClearedMileage(_franchiseeId, clearAmount, _purchaseId);
            FranchiseeCollection.FranchiseeData memory franchisee = franchiseeCollection.franchiseeOf(_franchiseeId);
            if (franchisee.email != NULL) {
                mileageLedger[franchisee.email] += clearAmount;
                emit ProvidedMileageToFranchisee(
                    franchisee.email,
                    clearAmount,
                    clearAmount,
                    mileageLedger[franchisee.email],
                    _franchiseeId
                );
            }
        }

        nonce[_signer]++;

        emit PaidMileage(_email, _amount, _amount, mileageLedger[_email], _purchaseId);
    }

    /// @notice 토큰을 구매에 사용하는 함수
    /// @dev 중계서버를 통해서 호출됩니다.
    /// @param _purchaseId 구매 아이디
    /// @param _amount 구매 금액
    /// @param _email 구매한 사용자의 이메일 해시
    /// @param _franchiseeId 구매한 가맹점 아이디
    /// @param _signer 구매자의 주소
    /// @param _signature 서명
    function payToken(
        string memory _purchaseId,
        uint256 _amount,
        bytes32 _email,
        string memory _franchiseeId,
        address _signer,
        bytes calldata _signature
    ) public {
        bytes32 dataHash = keccak256(abi.encode(_purchaseId, _amount, _email, _franchiseeId, _signer, nonce[_signer]));
        require(ECDSA.recover(ECDSA.toEthSignedMessageHash(dataHash), _signature) == _signer, "Invalid signature");
        address userAddress = linkCollection.toAddress(_email);
        require(userAddress != address(0x00), "Unregistered email-address");
        require(userAddress == _signer, "Invalid address");

        uint256 amountToken = convertMileageToToken(_amount);
        require(tokenLedger[_email] >= amountToken, "Insufficient balance");

        tokenLedger[_email] -= amountToken;
        tokenLedger[foundationAccount] += amountToken;
        franchiseeCollection.addUsedMileage(_franchiseeId, _amount, _purchaseId);

        uint256 clearAmount = franchiseeCollection.getClearMileage(_franchiseeId);
        if (clearAmount > 0) {
            franchiseeCollection.addClearedMileage(_franchiseeId, clearAmount, _purchaseId);
            FranchiseeCollection.FranchiseeData memory franchisee = franchiseeCollection.franchiseeOf(_franchiseeId);
            if (franchisee.email != NULL) {
                mileageLedger[franchisee.email] += clearAmount;
                emit ProvidedMileageToFranchisee(
                    franchisee.email,
                    clearAmount,
                    clearAmount,
                    mileageLedger[franchisee.email],
                    _franchiseeId
                );
            }
        }

        nonce[_signer]++;

        emit PaidToken(_email, amountToken, _amount, tokenLedger[_email], _purchaseId);
    }

    function convertMileageToToken(uint256 amount) internal view returns (uint256) {
        uint256 price = tokenPrice.get("KRW");
        return (amount * tokenPrice.MULTIPLE()) / price;
    }

    function convertTokenToMileage(uint256 amount) internal view returns (uint256) {
        uint256 price = tokenPrice.get("KRW");
        return (amount * price) / tokenPrice.MULTIPLE();
    }

    /// @notice 토큰을 예치합니다.
    /// @param _amount 금액
    function deposit(uint256 _amount) public {
        bytes32 email = linkCollection.toEmail(msg.sender);
        require(email != bytes32(0x00), "Unregistered email-address");

        require(_amount <= token.allowance(msg.sender, address(this)), "Not allowed deposit");
        token.transferFrom(msg.sender, address(this), _amount);

        tokenLedger[email] += _amount;

        uint256 amountMileage = convertTokenToMileage(_amount);
        emit Deposited(email, _amount, amountMileage, tokenLedger[email], msg.sender);
    }

    /// @notice 토큰을 인출합니다.
    /// @param _amount 금액
    function withdraw(uint256 _amount) public {
        bytes32 email = linkCollection.toEmail(msg.sender);
        require(email != bytes32(0x00), "Unregistered email-address");

        require(_amount <= tokenLedger[email], "Insufficient balance");
        token.transfer(msg.sender, _amount);

        tokenLedger[email] -= _amount;

        uint256 amountMileage = convertTokenToMileage(_amount);
        emit Withdrawn(email, _amount, amountMileage, tokenLedger[email], msg.sender);
    }

    /// @notice 마일리지를 토큰으로 교환합니다
    /// @dev 중계서버를 통해서 호출됩니다.
    /// @param _email 사용자의 이메일 해시
    /// @param _amountMileage 교환할 마일리지의 량
    /// @param _signer 사용자의 주소
    /// @param _signature 서명
    function exchangeMileageToToken(
        bytes32 _email,
        uint256 _amountMileage,
        address _signer,
        bytes calldata _signature
    ) public {
        bytes32 dataHash = keccak256(abi.encode(_email, _amountMileage, _signer, nonce[_signer]));
        require(ECDSA.recover(ECDSA.toEthSignedMessageHash(dataHash), _signature) == _signer, "Invalid signature");
        address userAddress = linkCollection.toAddress(_email);
        require(userAddress != address(0x00), "Unregistered email-address");
        require(userAddress == _signer, "Invalid address");

        require(mileageLedger[_email] >= _amountMileage, "Insufficient balance");

        uint256 amountToken = convertMileageToToken(_amountMileage);
        require(tokenLedger[foundationAccount] >= amountToken, "Insufficient foundation balance");

        mileageLedger[_email] -= _amountMileage;

        tokenLedger[_email] += amountToken;
        tokenLedger[foundationAccount] -= amountToken;

        nonce[_signer]++;

        emit ExchangedMileageToToken(_email, _amountMileage, amountToken, mileageLedger[_email], tokenLedger[_email]);
    }

    /// @notice 토큰을 마일리지로 교환합니다
    /// @dev 중계서버를 통해서 호출됩니다.
    /// @param _email 사용자의 이메일 해시
    /// @param _amountToken 교환할 토큰의 량
    /// @param _signer 사용자의 주소
    /// @param _signature 서명
    function exchangeTokenToMileage(
        bytes32 _email,
        uint256 _amountToken,
        address _signer,
        bytes calldata _signature
    ) public {
        bytes32 dataHash = keccak256(abi.encode(_email, _amountToken, _signer, nonce[_signer]));
        require(ECDSA.recover(ECDSA.toEthSignedMessageHash(dataHash), _signature) == _signer, "Invalid signature");
        address userAddress = linkCollection.toAddress(_email);
        require(userAddress != address(0x00), "Unregistered email-address");
        require(userAddress == _signer, "Invalid address");

        require(tokenLedger[_email] >= _amountToken, "Insufficient balance");

        tokenLedger[_email] -= _amountToken;
        tokenLedger[foundationAccount] += _amountToken;

        uint256 amountMileage = convertTokenToMileage(_amountToken);
        mileageLedger[_email] += amountMileage;

        nonce[_signer]++;

        emit ExchangedTokenToMileage(_email, amountMileage, _amountToken, mileageLedger[_email], tokenLedger[_email]);
    }

    /// @notice 마일리지의 잔고를 리턴한다
    /// @param _hash 이메일의 해시
    function mileageBalanceOf(bytes32 _hash) public view returns (uint256) {
        return mileageLedger[_hash];
    }

    /// @notice 토큰의 잔고를 리턴한다
    /// @param _hash 이메일의 해시
    function tokenBalanceOf(bytes32 _hash) public view returns (uint256) {
        return tokenLedger[_hash];
    }

    /// @notice nonce를  리턴한다
    /// @param _account 지갑주소
    function nonceOf(address _account) public view returns (uint256) {
        return nonce[_account];
    }

    /// @notice 구매 데이터를 리턴한다
    /// @param _purchaseId 구매 아이디
    function purchaseOf(string memory _purchaseId) public view returns (PurchaseData memory) {
        return purchases[_purchaseId];
    }

    /// @notice 구매 데이터의 아이디를 리턴한다
    /// @param _idx 배열의 순번
    function purchaseIdOf(uint256 _idx) public view returns (string memory) {
        return purchaseIds[_idx];
    }

    /// @notice 구매 데이터의 갯수를 리턴한다
    function purchasesLength() public view returns (uint256) {
        return purchaseIds.length;
    }
}
