// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin's battle-tested ERC-20 implementation
// This gives us standard token functionality (transfer, approve, balanceOf)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// Ownable restricts sensitive functions to the contract owner (our backend)
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * CarbonCredit Contract
 *
 * Each token = 1 tCO2 carbon credit
 * Only the verified backend (owner) can mint credits
 * Buffer credits are held in escrow inside this contract
 * Credits are burned (retired) when a company offsets their emissions
 * Fraud detected = buffer burned + debt recorded on-chain
 */
contract CarbonCredit is ERC20, Ownable {

    // ── STRUCTS ──────────────────────────────────────────────────────────────

    // Stores everything about one verification event permanently on-chain
    struct VerificationRecord {
        string  projectId;          // UUID from our PostgreSQL database
        string  imageHash;          // SHA-256 hash of satellite image metadata
        uint256 ndviBasisPoints;    // NDVI × 10000 (solidity has no decimals)
        uint256 confidenceScore;    // 0-100, from ML scoring
        uint256 creditsIssued;      // total credits calculated
        uint256 bufferCredits;      // 15% held in escrow
        uint256 activeCredits;      // credits minted to company wallet
        uint256 timestamp;          // when this was recorded
        bool    isValid;            // false if fraud detected later
    }

    // Tracks debt when fraud is proven after credits were already issued
    struct DebtRecord {
        uint256 amount;             // credits owed back
        uint256 createdAt;          // when debt was recorded
        bool    cleared;            // true when company has paid back
    }

    // ── STATE VARIABLES ──────────────────────────────────────────────────────

    // verification_id → VerificationRecord
    mapping(string => VerificationRecord) public verifications;

    // project_id → list of verification IDs (one per annual survey)
    mapping(string => string[]) public projectVerifications;

    // project_id → buffer credits held in escrow for that project
    mapping(string => uint256) public escrowBalance;

    // company wallet → debt record (if fraud detected)
    mapping(address => DebtRecord) public debts;

    // company wallet → bool (blocked from receiving new credits)
    mapping(address => bool) public blockedWallets;

    // verification_id → bool (retired = credits burned, offset proven)
    mapping(string => bool) public retiredVerifications;

    // ── EVENTS ───────────────────────────────────────────────────────────────
    // Events are the blockchain's equivalent of logs — anyone can monitor them

    event CreditsIssued(
        string  indexed projectId,
        address indexed companyWallet,
        uint256 activeCredits,
        uint256 bufferCredits,
        string  verificationId,
        string  imageHash
    );

    event CreditsRetired(
        string  indexed projectId,
        address indexed retiredBy,
        uint256 amount,
        string  verificationId
    );

    event FraudDetected(
        string  indexed projectId,
        address indexed companyWallet,
        uint256 bufferBurned,
        uint256 debtRecorded
    );

    event DebtCleared(
        address indexed companyWallet,
        uint256 amount
    );

    event BufferReleased(
        string  indexed projectId,
        address indexed companyWallet,
        uint256 amount
    );

    // ── CONSTRUCTOR ──────────────────────────────────────────────────────────

    constructor() ERC20("Carbon Credit", "CCT") Ownable(msg.sender) {
        // "CCT" = Carbon Credit Token
        // msg.sender = the wallet that deploys this contract (our backend wallet)
        // Only this wallet can call onlyOwner functions
    }

    // ── CORE FUNCTIONS ───────────────────────────────────────────────────────

    /**
     * mintCredits — Called by our FastAPI backend after a PASS verification
     *
     * Only the contract owner (our deployer wallet) can call this.
     * Records everything permanently on-chain, mints active credits to company.
     * Buffer credits stay inside this contract as escrow.
     *
     * @param projectId         UUID from PostgreSQL
     * @param verificationId    UUID of this specific verification
     * @param imageHash         SHA-256 hash of satellite image metadata
     * @param companyWallet     Where to send the active credits
     * @param ndviBasisPoints   NDVI × 10000 (e.g. 0.4136 → 4136)
     * @param confidenceScore   ML confidence 0-100
     * @param activeCredits     Credits to mint to company wallet
     * @param bufferCredits     Credits to hold in escrow
     */
    function mintCredits(
        string  memory projectId,
        string  memory verificationId,
        string  memory imageHash,
        address        companyWallet,
        uint256        ndviBasisPoints,
        uint256        confidenceScore,
        uint256        activeCredits,
        uint256        bufferCredits
    ) external onlyOwner {

        // Prevent duplicate minting for the same verification
        require(
            verifications[verificationId].timestamp == 0,
            "Verification already recorded"
        );

        // Blocked wallets cannot receive credits until debt is cleared
        require(
            !blockedWallets[companyWallet],
            "Wallet blocked due to outstanding debt - clear debt first"
        );

        uint256 totalCredits = activeCredits + bufferCredits;

        // Store the permanent on-chain verification record
        verifications[verificationId] = VerificationRecord({
            projectId        : projectId,
            imageHash        : imageHash,
            ndviBasisPoints  : ndviBasisPoints,
            confidenceScore  : confidenceScore,
            creditsIssued    : totalCredits,
            bufferCredits    : bufferCredits,
            activeCredits    : activeCredits,
            timestamp        : block.timestamp,
            isValid          : true
        });

        // Link this verification to the project
        projectVerifications[projectId].push(verificationId);

        // Add buffer to escrow — stays in contract until next verification passes
        escrowBalance[projectId] += bufferCredits;

        // Mint active credits directly to company wallet
        // _mint is ERC-20's internal function — creates new tokens
        if (activeCredits > 0) {
            _mint(companyWallet, activeCredits);
        }

        // Mint buffer credits to this contract itself (escrow)
        if (bufferCredits > 0) {
            _mint(address(this), bufferCredits);
        }

        emit CreditsIssued(
            projectId,
            companyWallet,
            activeCredits,
            bufferCredits,
            verificationId,
            imageHash
        );
    }

    /**
     * releaseBuffer — Called when next annual verification passes
     * Releases the previous year's escrowed buffer to the company wallet
     *
     * @param projectId      The project whose buffer to release
     * @param companyWallet  Where to send the released buffer
     */
    function releaseBuffer(
        string  memory projectId,
        address        companyWallet
    ) external onlyOwner {

        uint256 amount = escrowBalance[projectId];
        require(amount > 0, "No buffer in escrow for this project");
        require(!blockedWallets[companyWallet], "Wallet is blocked");

        // Clear escrow before transfer (prevents re-entrancy)
        escrowBalance[projectId] = 0;

        // Transfer from contract's balance to company wallet
        _transfer(address(this), companyWallet, amount);

        emit BufferReleased(projectId, companyWallet, amount);
    }

    /**
     * retireCredits — Called when a polluting company offsets their emissions
     * Burns tokens permanently — this is the proof of carbon offset
     *
     * @param amount          How many credits to retire
     * @param verificationId  Which verification these credits came from
     * @param projectId       The project being offset against
     */
    function retireCredits(
        uint256 amount,
        string  memory verificationId,
        string  memory projectId
    ) external {

        // The caller must have enough credits to retire
        require(balanceOf(msg.sender) >= amount, "Insufficient credits to retire");
        require(amount > 0, "Amount must be greater than zero");

        // _burn destroys tokens permanently — they can never be recovered
        _burn(msg.sender, amount);

        retiredVerifications[verificationId] = true;

        emit CreditsRetired(projectId, msg.sender, amount, verificationId);
    }

    /**
     * flagFraud — Called when fraud is proven after credits were already issued
     * Burns the buffer, records a debt, blocks the wallet
     *
     * @param projectId      The fraudulent project
     * @param companyWallet  The fraudster's wallet
     * @param debtAmount     How many credits must be paid back (active credits already issued)
     */
    function flagFraud(
        string  memory projectId,
        address        companyWallet,
        uint256        debtAmount
    ) external onlyOwner {

        // Burn whatever is in escrow for this project
        uint256 bufferToBurn = escrowBalance[projectId];
        if (bufferToBurn > 0) {
            escrowBalance[projectId] = 0;
            _burn(address(this), bufferToBurn);
        }

        // Record the debt — company must pay this back before any future credits
        debts[companyWallet] = DebtRecord({
            amount    : debtAmount,
            createdAt : block.timestamp,
            cleared   : false
        });

        // Block this wallet from receiving future credits
        blockedWallets[companyWallet] = true;

        emit FraudDetected(projectId, companyWallet, bufferToBurn, debtAmount);
    }

    /**
     * clearDebt — Called when a company has paid back fraudulent credits
     * Unblocks their wallet so they can participate again
     *
     * @param companyWallet  The wallet to unblock
     */
    function clearDebt(address companyWallet) external onlyOwner {
        require(debts[companyWallet].amount > 0, "No debt recorded for this wallet");

        debts[companyWallet].cleared = true;
        blockedWallets[companyWallet] = false;

        emit DebtCleared(companyWallet, debts[companyWallet].amount);
    }

    // ── VIEW FUNCTIONS ───────────────────────────────────────────────────────
    // These are read-only — no gas cost, anyone can call them

    /**
     * getVerification — Returns the full on-chain record for a verification
     * This is what BEE/MoEFCC calls to audit any project
     */
    function getVerification(string memory verificationId)
        external view
        returns (VerificationRecord memory)
    {
        return verifications[verificationId];
    }

    /**
     * getProjectVerifications — Returns all verification IDs for a project
     */
    function getProjectVerifications(string memory projectId)
        external view
        returns (string[] memory)
    {
        return projectVerifications[projectId];
    }

    /**
     * getEscrowBalance — Returns buffer credits held for a project
     */
    function getEscrowBalance(string memory projectId)
        external view
        returns (uint256)
    {
        return escrowBalance[projectId];
    }

    /**
     * isWalletBlocked — Check if a wallet is blocked due to fraud
     */
    function isWalletBlocked(address wallet) external view returns (bool) {
        return blockedWallets[wallet];
    }
}