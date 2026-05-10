// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Imago Labs / Metamorphic Curations LLC
pragma solidity 0.8.20;

/**
 * @title  AletheiaPool V2
 * @notice Discretionary mutual protection protocol for the agentic economy.
 *
 *         V2 fixes (vs V1):
 *         [P0] Elite tier (4) added — purchasePolicy no longer reverts on tier=4
 *         [P0] tierLimits corrected: Standard=$100, Pro=$500, Elite=$2000 USDC
 *         [P0] fileClaim now collects 10 USDC claim bond via transferFrom
 *         [P0] resolveClaim: bond returned on upheld, forfeited to pool on reject
 *         [P0] resolveClaim: CEI pattern fixed — state updated before external call
 *         [P1] resolveClaim: policy expiry re-checked before payout
 *         [NEW] Pausable circuit breaker — owner can pause all member actions
 *         [NEW] Reserve ratio guard — new policies blocked below 120% reserve
 *         [NEW] Time-locked oracle update — 24 h delay before new oracle takes effect
 *         [NEW] Policy renewal function
 *         [NEW] Tool manifest hash stored in AgentProfile (ASF Layer 1)
 *         [NEW] renewPolicy function for seamless coverage continuation
 */

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AletheiaPool {

    // =========================================================================
    // Constants
    // =========================================================================

    uint256 public constant CLAIM_BOND         = 10_000_000;   // 10 USDC (6 decimals)
    uint256 public constant ORACLE_TIMELOCK    = 24 hours;
    uint256 public constant MIN_RESERVE_BPS    = 12_000;       // 120 % in basis points
    uint256 public constant MAX_DURATION_DAYS  = 365;

    // =========================================================================
    // Types — Layer 2 (mutual pool)
    // =========================================================================

    enum ClaimStatus { Pending, Upheld, Rejected, Paid }

    struct Policy {
        address member;
        uint8   tier;
        uint256 contributionPaid;   // renamed from premiumPaid for clarity
        uint256 coverageLimit;
        uint256 activatedAt;
        uint256 expiresAt;
        bool    active;
    }

    struct Claim {
        bytes32     claimId;
        address     claimant;
        bytes32     policyId;
        uint8       category;
        uint256     claimedAmount;
        string      evidenceHash;
        ClaimStatus status;
        uint256     filedAt;
        uint256     bondAmount;     // NEW: bond locked at filing
    }

    // =========================================================================
    // Types — Layer 1 (agent risk registry)
    // =========================================================================

    struct AgentProfile {
        bytes32 agentId;
        address operator;
        string  name;
        string  description;
        string  modelFamily;
        uint8   permissionScope;          // 1=readonly … 5=autonomous
        uint8   oversightLevel;           // 1=every action … 3=fully autonomous
        uint8   domain;                   // 1=general 2=financial 3=healthcare 4=legal 5=infra
        bool    requiresHumanConfirmation;
        bytes32 systemPromptHash;
        bytes32 toolManifestHash;         // NEW: keccak256 of declared tool set (ASF Layer 1)
        uint8   riskScore;                // 0-100, set by oracle
        uint8   riskTier;                 // 1=Supervised … 4=HighAutonomy
        bool    registered;
        bool    requiresReregistration;
        uint256 registeredAt;
        uint256 totalActions;
        uint256 totalDisputes;
    }

    struct ActionLog {
        bytes32 actionId;
        bytes32 agentId;
        bytes32 policyId;
        string  actionType;
        string  description;
        bytes32 runtimePromptHash;
        bool    humanConfirmationPresent;
        uint256 timestamp;
        bool    flagged;
    }

    // =========================================================================
    // State
    // =========================================================================

    address public owner;
    address public oracle;

    // Time-locked oracle rotation
    address public pendingOracle;
    uint256 public oracleUnlockTime;

    IERC20 public immutable usdc;

    bool public paused;

    uint256 public totalStaked;
    uint256 public totalPaidOut;
    uint256 public totalClaimBondsHeld;   // bonds currently escrowed
    uint256 public nonce;

    // Tiers 1=Basic 2=Standard 3=Pro 4=Elite — index 0 unused
    uint256[5] public tierContributions;   // monthly USDC contribution (6 dec)
    uint256[5] public tierLimits;          // max coverage per policy (6 dec)

    mapping(bytes32 => Policy) public policies;
    mapping(bytes32 => Claim)  public claims;
    mapping(address => bytes32[]) public memberPolicies;
    mapping(address => bytes32[]) public memberClaims;

    uint256 public activePolicyCount;
    uint256 public totalCoverageExposure;  // sum of active coverageLimit values

    // Layer 1 — agent registry
    mapping(bytes32 => AgentProfile)    public agents;
    mapping(address => bytes32[])       public operatorAgents;
    mapping(bytes32 => bytes32[])       public agentActions;
    mapping(bytes32 => ActionLog)       public actionLogs;
    uint256 public totalRegisteredAgents;

    // =========================================================================
    // Events — Layer 2
    // =========================================================================

    event PolicyPurchased(
        bytes32 indexed policyId,
        address indexed member,
        uint8   tier,
        uint256 contributionPaid,
        uint256 coverageLimit,
        uint256 expiresAt
    );

    event PolicyRenewed(
        bytes32 indexed oldPolicyId,
        bytes32 indexed newPolicyId,
        address indexed member,
        uint8   tier,
        uint256 expiresAt
    );

    event ClaimFiled(
        bytes32 indexed claimId,
        address indexed claimant,
        bytes32 indexed policyId,
        uint8   category,
        uint256 claimedAmount,
        string  evidenceHash,
        uint256 bondAmount
    );

    event ClaimResolved(
        bytes32 indexed claimId,
        ClaimStatus status,
        uint256 timestamp
    );

    event PayoutSent(
        bytes32 indexed claimId,
        address indexed claimant,
        uint256 amount
    );

    event BondReturned(bytes32 indexed claimId, address indexed claimant, uint256 amount);
    event BondForfeited(bytes32 indexed claimId, uint256 amount);

    event CapitalStaked(address indexed staker, uint256 amount);

    event OracleRotationProposed(address indexed proposed, uint256 unlockTime);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // =========================================================================
    // Events — Layer 1
    // =========================================================================

    event AgentRegistered(
        bytes32 indexed agentId,
        address indexed operator,
        string  name,
        uint8   permissionScope,
        uint8   domain
    );

    event RiskScoreAssigned(
        bytes32 indexed agentId,
        uint8   riskScore,
        uint8   riskTier
    );

    event ActionLogged(
        bytes32 indexed actionId,
        bytes32 indexed agentId,
        string  actionType,
        bool    humanConfirmationPresent,
        bool    flagged
    );

    event AgentFlaggedForReregistration(bytes32 indexed agentId);

    event DeviationDetected(
        bytes32 indexed agentId,
        bytes32 indexed actionId,
        string  reason
    );

    event ToolManifestChanged(
        bytes32 indexed agentId,
        bytes32 oldHash,
        bytes32 newHash
    );

    // =========================================================================
    // Modifiers
    // =========================================================================

    modifier onlyOwner() {
        require(msg.sender == owner, "ALETHEIA: not owner");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "ALETHEIA: not oracle");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "ALETHEIA: paused");
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(address _usdc, address _oracle) {
        require(_usdc   != address(0), "ALETHEIA: usdc zero");
        require(_oracle != address(0), "ALETHEIA: oracle zero");

        owner  = msg.sender;
        oracle = _oracle;
        usdc   = IERC20(_usdc);

        // Monthly contributions in USDC (6 decimals)
        tierContributions[1] =     2_000_000;   // Basic    $2
        tierContributions[2] =     5_000_000;   // Standard $5
        tierContributions[3] =    15_000_000;   // Pro      $15
        tierContributions[4] =    50_000_000;   // Elite    $50

        // Coverage limits in USDC (6 decimals)  — CORRECTED from V1
        tierLimits[1] =     50_000_000;   // Basic      $50
        tierLimits[2] =    100_000_000;   // Standard  $100
        tierLimits[3] =    500_000_000;   // Pro       $500
        tierLimits[4] =  2_000_000_000;   // Elite   $2,000
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /**
     * @dev Returns the free pool balance: contract USDC minus escrowed bonds.
     */
    function _freePool() internal view returns (uint256) {
        uint256 bal = usdc.balanceOf(address(this));
        return bal > totalClaimBondsHeld ? bal - totalClaimBondsHeld : 0;
    }

    /**
     * @dev Enforce 120 % reserve ratio: freePool >= 1.2 × totalCoverageExposure.
     *      Called before issuing a new policy.
     */
    function _checkReserve(uint256 newLimit) internal view {
        uint256 newExposure = totalCoverageExposure + newLimit;
        // freePool * 10_000 >= newExposure * MIN_RESERVE_BPS
        require(
            _freePool() * 10_000 >= newExposure * MIN_RESERVE_BPS,
            "ALETHEIA: reserve ratio insufficient"
        );
    }

    // =========================================================================
    // Layer 2 — Member actions
    // =========================================================================

    /**
     * @notice Purchase a coverage policy.
     * @param tier         1=Basic 2=Standard 3=Pro 4=Elite
     * @param durationDays Coverage duration (1–365 days)
     */
    function purchasePolicy(uint8 tier, uint256 durationDays)
        external
        whenNotPaused
        returns (bytes32)
    {
        require(tier >= 1 && tier <= 4, "ALETHEIA: bad tier");
        require(durationDays > 0 && durationDays <= MAX_DURATION_DAYS, "ALETHEIA: bad duration");

        uint256 contribution = tierContributions[tier];
        uint256 limit        = tierLimits[tier];

        // Reserve ratio guard
        _checkReserve(limit);

        require(
            usdc.transferFrom(msg.sender, address(this), contribution),
            "ALETHEIA: usdc transfer failed"
        );

        nonce += 1;
        bytes32 policyId = keccak256(
            abi.encodePacked(msg.sender, block.timestamp, nonce)
        );

        policies[policyId] = Policy({
            member:           msg.sender,
            tier:             tier,
            contributionPaid: contribution,
            coverageLimit:    limit,
            activatedAt:      block.timestamp,
            expiresAt:        block.timestamp + (durationDays * 1 days),
            active:           true
        });

        memberPolicies[msg.sender].push(policyId);
        activePolicyCount     += 1;
        totalCoverageExposure += limit;

        emit PolicyPurchased(policyId, msg.sender, tier, contribution, limit, policies[policyId].expiresAt);
        return policyId;
    }

    /**
     * @notice Renew an existing policy for another duration period.
     *         Deactivates the old policy and issues a fresh one at the same tier.
     * @param policyId     The policy being renewed
     * @param durationDays New duration (1–365 days)
     */
    function renewPolicy(bytes32 policyId, uint256 durationDays)
        external
        whenNotPaused
        returns (bytes32 newPolicyId)
    {
        Policy storage old = policies[policyId];
        require(old.member == msg.sender, "ALETHEIA: not policy owner");
        require(old.active,               "ALETHEIA: policy inactive");
        require(durationDays > 0 && durationDays <= MAX_DURATION_DAYS, "ALETHEIA: bad duration");

        uint8   tier         = old.tier;
        uint256 contribution = tierContributions[tier];
        uint256 limit        = tierLimits[tier];

        // Reserve ratio: deduct old limit from exposure first (it's being replaced)
        uint256 exposureWithout = totalCoverageExposure > limit
            ? totalCoverageExposure - limit : 0;
        require(
            _freePool() * 10_000 >= (exposureWithout + limit) * MIN_RESERVE_BPS,
            "ALETHEIA: reserve ratio insufficient"
        );

        // Deactivate old policy
        old.active = false;
        activePolicyCount     -= 1;
        totalCoverageExposure -= limit;

        // Collect new contribution
        require(
            usdc.transferFrom(msg.sender, address(this), contribution),
            "ALETHEIA: usdc transfer failed"
        );

        nonce += 1;
        newPolicyId = keccak256(
            abi.encodePacked(msg.sender, block.timestamp, nonce)
        );

        policies[newPolicyId] = Policy({
            member:           msg.sender,
            tier:             tier,
            contributionPaid: contribution,
            coverageLimit:    limit,
            activatedAt:      block.timestamp,
            expiresAt:        block.timestamp + (durationDays * 1 days),
            active:           true
        });

        memberPolicies[msg.sender].push(newPolicyId);
        activePolicyCount     += 1;
        totalCoverageExposure += limit;

        emit PolicyRenewed(policyId, newPolicyId, msg.sender, tier, policies[newPolicyId].expiresAt);
        return newPolicyId;
    }

    /**
     * @notice File a claim against an active policy.
     *         A 10 USDC claim bond is collected at filing.
     *         Bond is returned if upheld, forfeited if rejected.
     */
    function fileClaim(
        bytes32        policyId,
        uint8          category,
        uint256        claimedAmount,
        string calldata evidenceHash
    ) external whenNotPaused returns (bytes32) {
        Policy storage p = policies[policyId];
        require(p.member     == msg.sender,         "ALETHEIA: not policy owner");
        require(p.active,                           "ALETHEIA: policy inactive");
        require(block.timestamp <= p.expiresAt,     "ALETHEIA: policy expired");
        require(category >= 1 && category <= 4,     "ALETHEIA: bad category");
        require(claimedAmount > 0,                  "ALETHEIA: zero amount");
        require(claimedAmount <= p.coverageLimit,   "ALETHEIA: exceeds limit");

        // [P0 FIX] Collect claim bond
        require(
            usdc.transferFrom(msg.sender, address(this), CLAIM_BOND),
            "ALETHEIA: bond transfer failed"
        );
        totalClaimBondsHeld += CLAIM_BOND;

        nonce += 1;
        bytes32 claimId = keccak256(
            abi.encodePacked(msg.sender, policyId, block.timestamp, nonce)
        );

        claims[claimId] = Claim({
            claimId:       claimId,
            claimant:      msg.sender,
            policyId:      policyId,
            category:      category,
            claimedAmount: claimedAmount,
            evidenceHash:  evidenceHash,
            status:        ClaimStatus.Pending,
            filedAt:       block.timestamp,
            bondAmount:    CLAIM_BOND
        });

        memberClaims[msg.sender].push(claimId);

        emit ClaimFiled(claimId, msg.sender, policyId, category, claimedAmount, evidenceHash, CLAIM_BOND);
        return claimId;
    }

    // =========================================================================
    // Layer 2 — Oracle actions
    // =========================================================================

    /**
     * @notice Resolve a pending claim.
     *         Upheld  → payout claimedAmount + return bond to claimant.
     *         Rejected → forfeit bond to pool.
     *
     *         [P0 FIX] CEI pattern: all state mutations before external calls.
     *         [P1 FIX] Policy expiry re-checked at resolution time.
     */
    function resolveClaim(bytes32 claimId, bool upheld) external onlyOracle {
        Claim storage c = claims[claimId];
        require(c.claimId  != bytes32(0),          "ALETHEIA: claim missing");
        require(c.status   == ClaimStatus.Pending, "ALETHEIA: not pending");

        Policy storage p = policies[c.policyId];

        // [P1 FIX] Re-verify policy still valid at resolution time
        require(p.active,                          "ALETHEIA: policy deactivated");
        require(block.timestamp <= p.expiresAt,    "ALETHEIA: policy expired at resolution");

        uint256 bond   = c.bondAmount;
        address payee  = c.claimant;

        if (upheld) {
            uint256 payout = c.claimedAmount;

            // [P0 FIX] CEI — update state BEFORE external calls
            c.status = ClaimStatus.Paid;
            totalPaidOut        += payout;
            totalClaimBondsHeld -= bond;

            emit ClaimResolved(claimId, ClaimStatus.Upheld, block.timestamp);

            // External calls after state is settled
            require(
                usdc.balanceOf(address(this)) >= payout + bond,
                "ALETHEIA: pool insufficient"
            );
            require(usdc.transfer(payee, payout + bond), "ALETHEIA: payout failed");

            emit PayoutSent(claimId, payee, payout);
            emit BondReturned(claimId, payee, bond);
            emit ClaimResolved(claimId, ClaimStatus.Paid, block.timestamp);

        } else {
            // [P0 FIX] CEI — update state BEFORE anything
            c.status = ClaimStatus.Rejected;
            totalClaimBondsHeld -= bond;
            // Bond stays in contract — forfeited to pool

            emit ClaimResolved(claimId, ClaimStatus.Rejected, block.timestamp);
            emit BondForfeited(claimId, bond);
        }
    }

    // =========================================================================
    // Layer 2 — Liquidity
    // =========================================================================

    function stakeCapital(uint256 amount) external {
        require(amount > 0, "ALETHEIA: zero stake");
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "ALETHEIA: stake transfer failed"
        );
        totalStaked += amount;
        emit CapitalStaked(msg.sender, amount);
    }

    // =========================================================================
    // Admin — circuit breaker
    // =========================================================================

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // =========================================================================
    // Admin — time-locked oracle rotation
    // =========================================================================

    /**
     * @notice Propose a new oracle. The change takes effect after ORACLE_TIMELOCK (24 h).
     */
    function proposeOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "ALETHEIA: oracle zero");
        pendingOracle   = _newOracle;
        oracleUnlockTime = block.timestamp + ORACLE_TIMELOCK;
        emit OracleRotationProposed(_newOracle, oracleUnlockTime);
    }

    /**
     * @notice Execute a previously proposed oracle change after the timelock expires.
     */
    function acceptOracle() external onlyOwner {
        require(pendingOracle   != address(0),         "ALETHEIA: no pending oracle");
        require(block.timestamp >= oracleUnlockTime,   "ALETHEIA: timelock active");
        emit OracleUpdated(oracle, pendingOracle);
        oracle        = pendingOracle;
        pendingOracle = address(0);
    }

    // =========================================================================
    // Layer 1 — Agent registry
    // =========================================================================

    /**
     * @notice Register an agent and record its declared risk profile.
     *         systemPromptHash and toolManifestHash are keccak256 hashes
     *         computed off-chain and stored here as immutable attestations.
     */
    function registerAgent(
        string  calldata name,
        string  calldata description,
        string  calldata modelFamily,
        uint8            permissionScope,
        uint8            oversightLevel,
        uint8            domain,
        bool             requiresHumanConfirmation,
        bytes32          systemPromptHash,
        bytes32          toolManifestHash           // NEW: ASF Layer 1
    ) external returns (bytes32 agentId) {
        require(permissionScope >= 1 && permissionScope <= 5, "ALETHEIA: bad scope");
        require(oversightLevel  >= 1 && oversightLevel  <= 3, "ALETHEIA: bad oversight");
        require(domain          >= 1 && domain          <= 5, "ALETHEIA: bad domain");

        nonce += 1;
        agentId = keccak256(
            abi.encodePacked(msg.sender, name, block.timestamp, nonce)
        );

        AgentProfile storage a = agents[agentId];
        a.agentId                   = agentId;
        a.operator                  = msg.sender;
        a.name                      = name;
        a.description               = description;
        a.modelFamily               = modelFamily;
        a.permissionScope           = permissionScope;
        a.oversightLevel            = oversightLevel;
        a.domain                    = domain;
        a.requiresHumanConfirmation = requiresHumanConfirmation;
        a.systemPromptHash          = systemPromptHash;
        a.toolManifestHash          = toolManifestHash;   // NEW
        a.riskScore                 = 0;
        a.riskTier                  = 0;
        a.registered                = true;
        a.requiresReregistration    = false;
        a.registeredAt              = block.timestamp;
        a.totalActions              = 0;
        a.totalDisputes             = 0;

        operatorAgents[msg.sender].push(agentId);
        totalRegisteredAgents += 1;

        emit AgentRegistered(agentId, msg.sender, name, permissionScope, domain);
        return agentId;
    }

    function assignRiskScore(
        bytes32 agentId,
        uint8   riskScore,
        uint8   riskTier
    ) external onlyOracle {
        require(agents[agentId].registered, "ALETHEIA: agent not found");
        require(riskScore <= 100,            "ALETHEIA: bad score");
        require(riskTier >= 1 && riskTier <= 4, "ALETHEIA: bad tier");
        agents[agentId].riskScore = riskScore;
        agents[agentId].riskTier  = riskTier;
        emit RiskScoreAssigned(agentId, riskScore, riskTier);
    }

    /**
     * @notice Log a consequential agent action.
     *         Flags the action if:
     *           (a) runtimePromptHash differs from registered systemPromptHash
     *           (b) runtimeToolHash differs from registered toolManifestHash (NEW)
     *           (c) human confirmation required but not present
     */
    function logAction(
        bytes32        agentId,
        bytes32        policyId,
        string calldata actionType,
        string calldata description,
        bytes32         runtimePromptHash,
        bytes32         runtimeToolHash,          // NEW: ASF Layer 2
        bool            humanConfirmationPresent
    ) external returns (bytes32 actionId) {
        require(agents[agentId].registered, "ALETHEIA: agent not found");

        AgentProfile storage a = agents[agentId];

        bool promptDeviated  = (runtimePromptHash != a.systemPromptHash);
        bool toolDeviated    = (runtimeToolHash   != a.toolManifestHash);  // NEW
        bool missingConfirm  = (a.requiresHumanConfirmation && !humanConfirmationPresent);
        bool flagged         = promptDeviated || toolDeviated || missingConfirm;

        nonce += 1;
        actionId = keccak256(abi.encodePacked(agentId, block.timestamp, nonce));

        ActionLog storage log_ = actionLogs[actionId];
        log_.actionId                 = actionId;
        log_.agentId                  = agentId;
        log_.policyId                 = policyId;
        log_.actionType               = actionType;
        log_.description              = description;
        log_.runtimePromptHash        = runtimePromptHash;
        log_.humanConfirmationPresent = humanConfirmationPresent;
        log_.timestamp                = block.timestamp;
        log_.flagged                  = flagged;

        agentActions[agentId].push(actionId);
        a.totalActions += 1;

        emit ActionLogged(actionId, agentId, actionType, humanConfirmationPresent, flagged);

        if (promptDeviated) {
            emit DeviationDetected(agentId, actionId, "runtime_prompt_hash_mismatch");
        }
        if (toolDeviated) {
            emit DeviationDetected(agentId, actionId, "tool_manifest_hash_mismatch");
        }
        if (missingConfirm) {
            emit DeviationDetected(agentId, actionId, "missing_human_confirmation");
        }

        return actionId;
    }

    function flagAgentForReregistration(bytes32 agentId) external onlyOracle {
        require(agents[agentId].registered, "ALETHEIA: agent not found");
        agents[agentId].requiresReregistration = true;
        agents[agentId].totalDisputes         += 1;
        emit AgentFlaggedForReregistration(agentId);
    }

    // =========================================================================
    // Views — Layer 2
    // =========================================================================

    function getPolicy(bytes32 policyId) external view returns (Policy memory) {
        return policies[policyId];
    }

    function getClaim(bytes32 claimId) external view returns (Claim memory) {
        return claims[claimId];
    }

    function getPoolBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function getFreePool() external view returns (uint256) {
        return _freePool();
    }

    function getReserveRatioBps() external view returns (uint256) {
        if (totalCoverageExposure == 0) return type(uint256).max;
        return (_freePool() * 10_000) / totalCoverageExposure;
    }

    function getMemberPolicies(address member) external view returns (bytes32[] memory) {
        return memberPolicies[member];
    }

    function getActivePolicyCount() external view returns (uint256) {
        return activePolicyCount;
    }

    function getTotalPaidOut() external view returns (uint256) {
        return totalPaidOut;
    }

    // =========================================================================
    // Views — Layer 1
    // =========================================================================

    function getAgent(bytes32 agentId) external view returns (AgentProfile memory) {
        return agents[agentId];
    }

    function getActionLog(bytes32 actionId) external view returns (ActionLog memory) {
        return actionLogs[actionId];
    }

    function getAgentActions(bytes32 agentId) external view returns (bytes32[] memory) {
        return agentActions[agentId];
    }

    function getOperatorAgents(address operator) external view returns (bytes32[] memory) {
        return operatorAgents[operator];
    }

    function getTotalRegisteredAgents() external view returns (uint256) {
        return totalRegisteredAgents;
    }
}
