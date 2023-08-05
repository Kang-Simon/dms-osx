// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ValidatorCollection.sol";

/// @notice 마일리지와 토큰의 원장
contract Ledger {
    /// @notice 마일리지의 원장
    mapping(bytes32 => uint256) public mileageLedger;
    /// @notice 토큰의 원장
    mapping(bytes32 => uint256) public tokenLedger;

    struct PurchaseData {
        string purchaseId;
        uint256 timestamp;
        uint256 amount;
        bytes32 userEmail;
        string franchiseeId;
    }

    mapping(string => PurchaseData) public purchaseMap;
    string[] public purchaseIdList;

    address public tokenAddress;
    address public validatorAddress;

    IERC20 private token;
    ValidatorCollection private validatorCollection;

    /// @notice 검증자가 추가될 때 발생되는 이벤트
    event SavedPurchase(string purchaseId, uint256 timestamp, uint256 amount, bytes32 userEmail, string franchiseeId);
    /// @notice 마일리지가 지급될 때 발생되는 이벤트
    event ProvidedMileage(bytes32 email, uint256 amount);

    /// @notice 생성자
    /// @param _tokenAddress 토큰의 주소
    /// @param _validatorAddress 검증자컬랙션의 주소
    constructor(address _tokenAddress, address _validatorAddress) {
        tokenAddress = _tokenAddress;
        validatorAddress = _validatorAddress;

        token = IERC20(_tokenAddress);
        validatorCollection = ValidatorCollection(_validatorAddress);
    }

    modifier onlyValidator(address _account) {
        bool isValidator = false;
        for (uint256 i = 0; i < validatorCollection.getActiveItemsLength(); ++i) {
            if (_account == validatorCollection.activeItems(i)) {
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
    /// @param _userEmail 구매한 사용자의 이메일 해시
    /// @param _franchiseeId 구매한 가맹점 아이디
    function savePurchase(
        string memory _purchaseId,
        uint256 _timestamp,
        uint256 _amount,
        bytes32 _userEmail,
        string memory _franchiseeId
    ) public onlyValidator(msg.sender) {
        PurchaseData memory data = PurchaseData({
            purchaseId: _purchaseId,
            timestamp: _timestamp,
            amount: _amount,
            userEmail: _userEmail,
            franchiseeId: _franchiseeId
        });
        purchaseIdList.push(_purchaseId);
        purchaseMap[_purchaseId] = data;

        uint256 mileage = _amount / 100;
        provideMileage(_userEmail, mileage);

        emit SavedPurchase(_purchaseId, _timestamp, _amount, _userEmail, _franchiseeId);
    }

    /// @notice 마일리지를 지급합니다.
    /// @dev 구매데아타를 확인한 후 호출됩니다.
    /// @param _email 이메일 해시
    /// @param _amount 지급할 마일리지
    function provideMileage(bytes32 _email, uint256 _amount) internal {
        mileageLedger[_email] += _amount;

        emit ProvidedMileage(_email, _amount);
    }
}