// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import './interfaces/IToken.sol';
import './interfaces/IDexFactory.sol';
import './interfaces/IDexRouter02.sol';
import './libraries/Safemath.sol';
import './utils/Ownable.sol';

contract DONASWAP is IToken, Ownable {
    using SafeMath for uint256;
    
    mapping (address => uint256) private _reflections;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    
    mapping (address => bool) private _isExcludedFromFee;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _totalSupply = 100000 * 10**6 * 10**9;
    uint256 private _reflectionTotal = (MAX - (MAX % _totalSupply));
    uint256 private _takeFeeTotal;

    string private constant _name = "DONASWAP";
    string private constant _symbol = "DONA";
    uint8 private constant _decimals = 9;

    uint256 public _taxFee = 5;
    uint256 private _previousTaxFee = _taxFee;

    uint256 public _liquidityFee = 5;
    uint256 private _previousLiquidityFee = _liquidityFee;

    IDexRouter02 public dexRouter;
    address public dexPair;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;

    uint256 public _maxTransactionAmount = 500 * 10**6 * 10**9;
    uint256 private tokensToAddToLiquidity = 50 * 10**6 * 10**9;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 nativeReceived,
        uint256 tokensIntoLiquidity
    );

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false; 
    }

    constructor() {
        _reflections[_msgSender()] = _reflectionTotal;
        IDexRouter02 _dexRouter = IDexRouter02(0x6162e4bD45239416d2Ef198F5D03A968182A30E4);
         // Create a swap pair for this new token
        dexPair = IDexFactory(_dexRouter.factory())
            .createPair(address(this), _dexRouter.WETH());

        // set the rest of the contract variables
        dexRouter = _dexRouter;

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public pure returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {Token-balanceOf} and {Token-transfer}.
     */
    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {Token-totalSupply}.
     */
    function totalSupply() public pure returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {Token-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _balances[account];
        return tokenFromReflection(_reflections[account]);
    }

    /**
     * @dev See {Token-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    /**
     * @dev See {Token-allowance}.
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {Token-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {Token-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {Token}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(from, to, amount);
        _approve(from, _msgSender(), _allowances[from][_msgSender()].sub(amount, "Token: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IToken-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IToken-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "Token: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _takeFeeTotal;
    }

    function minimumTokensBeforeSwapAmount() public view returns (uint256) {
        return tokensToAddToLiquidity;
    }

    function deliver(uint256 totalAmount) public {
        address from = _msgSender();
        require(!_isExcluded[from], "Excluded addresses cannot call this function");
        (uint256 reflectionAmount,,,,,) = _getValues(totalAmount);
        _reflections[from] = _reflections[from].sub(reflectionAmount);
        _reflectionTotal = _reflectionTotal.sub(reflectionAmount);
        _takeFeeTotal = _takeFeeTotal.add(totalAmount);
    }

    function reflectionFromToken(uint256 totalAmount, bool deductTransferFee) public view returns (uint256) {
        require(totalAmount <= _totalSupply, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 reflectionAmount,,,,,) = _getValues(totalAmount);
            return reflectionAmount;
        } else {
            (,uint256 reflectedTransferAmount,,,,) = _getValues(totalAmount);
            return reflectedTransferAmount;
        }
    }

    function tokenFromReflection(uint256 reflectionAmount) public view returns (uint256) {
        require(reflectionAmount <= _reflectionTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return reflectionAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Account is not excluded");
        require(_excluded.length <= 50, "Excluded list is too long!");
            if (_reflections[account] > 0) {
                _balances[account] = tokenFromReflection(_reflections[account]);
            }
            _isExcluded[account] = true;
            _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is not excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                uint256 currentRate = _getRate();
                _reflections[account] = _balances[account].mul(currentRate);
                _balances[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }
  
    function _transferBothExcluded(address from, address to, uint256 totalAmount) private {
        (uint256 reflectionAmount, uint256 reflectedTransferAmount, uint256 reflectionFee, uint256 totalTransferAmount, uint256 taxedFee, uint256 takeLiquidity) = _getValues(totalAmount);
        _balances[from] = _balances[from].sub(totalAmount);
        _reflections[from] = _reflections[from].sub(reflectionAmount);
        _balances[to] = _balances[to].add(totalTransferAmount);
        _reflections[to] = _reflections[to].add(reflectedTransferAmount);        
        _reflectFee(reflectionFee, taxedFee);
        _takeLiquidity(takeLiquidity);
        emit Transfer(from, to, totalTransferAmount);
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setTaxFeePercent(uint256 taxFee) external onlyOwner {
        _taxFee = taxFee;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        _liquidityFee = liquidityFee;
    }

    function setMaxTransactionAmount(uint256 maxTransactionAmount) external onlyOwner {
        _maxTransactionAmount = _totalSupply.mul(maxTransactionAmount).div(10**2);
    }

    function setTokensToAddToLiquidity(uint256 _minimumTokensBeforeSwap) external onlyOwner() {
        tokensToAddToLiquidity = _minimumTokensBeforeSwap;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    // Recieve native coins from active router when swaping
    receive() external payable {}

    function _reflectFee(uint256 reflectionFee, uint256 taxedFee) private {
        _reflectionTotal = _reflectionTotal.sub(reflectionFee);
        _takeFeeTotal = _takeFeeTotal.add(taxedFee);
    }

    function _getValues(uint256 totalAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 totalTransferAmount, uint256 taxedFee, uint256 takeLiquidity) = _getTValues(totalAmount);
        (uint256 reflectionAmount, uint256 reflectedTransferAmount, uint256 reflectionFee) = _getRValues(totalAmount, taxedFee, takeLiquidity, _getRate());
        return (reflectionAmount, reflectedTransferAmount, reflectionFee, totalTransferAmount, taxedFee, takeLiquidity);
    }

    function _getTValues(uint256 totalAmount) private view returns (uint256, uint256, uint256) {
        uint256 taxedFee = calculateTaxFee(totalAmount);
        uint256 takeLiquidity = calculateLiquidityFee(totalAmount);
        uint256 totalTransferAmount = totalAmount.sub(taxedFee).sub(takeLiquidity);
        return (totalTransferAmount, taxedFee, takeLiquidity);
    }

    function _getRValues(uint256 totalAmount, uint256 taxedFee, uint256 takeLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 reflectionAmount = totalAmount.mul(currentRate);
        uint256 reflectionFee = taxedFee.mul(currentRate);
        uint256 reflectionsLiquidity = takeLiquidity.mul(currentRate);
        uint256 reflectedTransferAmount = reflectionAmount.sub(reflectionFee).sub(reflectionsLiquidity);
        return (reflectionAmount, reflectedTransferAmount, reflectionFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 reflectionSupply, uint256 tokenSupply) = _getCurrentSupply();
        return reflectionSupply.div(tokenSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 reflectionSupply = _reflectionTotal;
        uint256 tokenSupply = _totalSupply;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_reflections[_excluded[i]] > reflectionSupply || _balances[_excluded[i]] > tokenSupply) return (_reflectionTotal, _totalSupply);
            reflectionSupply = reflectionSupply.sub(_reflections[_excluded[i]]);
            tokenSupply = tokenSupply.sub(_balances[_excluded[i]]);
        }
        if (reflectionSupply < _reflectionTotal.div(_totalSupply)) return (_reflectionTotal, _totalSupply);
        return (reflectionSupply, tokenSupply);
    }

    function _takeLiquidity(uint256 takeLiquidity) private {
        uint256 currentRate = _getRate();
        uint256 reflectionsLiquidity = takeLiquidity.mul(currentRate);
        _reflections[address(this)] = _reflections[address(this)].add(reflectionsLiquidity);
        if(_isExcluded[address(this)])
            _balances[address(this)] = _balances[address(this)].add(takeLiquidity);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(10**2);
    }

    function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_liquidityFee).div(10**2);
    }

    function removeAllFee() private {
        if(_taxFee == 0 && _liquidityFee == 0) return;

        _previousTaxFee = _taxFee;
        _previousLiquidityFee = _liquidityFee;

        _taxFee = 0;
        _liquidityFee = 0;
    }

    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _liquidityFee = _previousLiquidityFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "Token: approve from the zero address");
        require(spender != address(0), "Token: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

   /**
     * @dev Moves tokens `amount` from `from` to `to`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "Token: transfer from the zero address");
        require(to != address(0), "Token: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner())
            require(amount <= _maxTransactionAmount, "Transfer amount exceeds the maxTxAmount.");

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if from is dex pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        if(contractTokenBalance >= _maxTransactionAmount)
        {
            contractTokenBalance = _maxTransactionAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= tokensToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != dexPair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = tokensToAddToLiquidity;
            // add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        // indicates if fee should be deducted from transfer
        bool takeFee = true;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        // transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current native balance.
        // this is so that we can capture exactly the amount of native that the
        // swap creates, and not make the liquidity event include any native that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for native currency
        swapTokensForNative(half); // <- this breaks the native currency -> swap when swap and liquify is triggered

        // how much native currency did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to swap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }
    
    function swapTokensForNative(uint256 tokenAmount) private {
        // generate the swap pair path of token -> wrapped native currency        
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        // make the swap
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of native currency
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 nativeAmount) private {
        // approve token transfer to cover all possible scenarios        
        _approve(address(this), address(dexRouter), tokenAmount);

        // add the liquidity
        dexRouter.addLiquidityETH{value: nativeAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    // this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address from, address to, uint256 amount, bool takeFee) private {
        if(!takeFee)
            removeAllFee();

        if (_isExcluded[from] && !_isExcluded[to]) {
            _transferFromExcluded(from, to, amount);
        } else if (!_isExcluded[from] && _isExcluded[to]) {
            _transferToExcluded(from, to, amount);
        } else if (_isExcluded[from] && _isExcluded[to]) {
            _transferBothExcluded(from, to, amount);
        } else {
            _transferStandard(from, to, amount);
        }

        if(!takeFee)
            restoreAllFee();
    }

    function _transferStandard(address from, address to, uint256 totalAmount) private {
        (uint256 reflectionAmount, uint256 reflectedTransferAmount, uint256 reflectionFee, uint256 totalTransferAmount, uint256 taxedFee, uint256 takeLiquidity) = _getValues(totalAmount);
        _reflections[from] = _reflections[from].sub(reflectionAmount);
        _reflections[to] = _reflections[to].add(reflectedTransferAmount);
        _takeLiquidity(takeLiquidity);
        _reflectFee(reflectionFee, taxedFee);
        emit Transfer(from, to, totalTransferAmount);
    }   
    
    function _transferToExcluded(address from, address to, uint256 totalAmount) private {
        (uint256 reflectionAmount, uint256 reflectedTransferAmount, uint256 reflectionFee, uint256 totalTransferAmount, uint256 taxedFee, uint256 takeLiquidity) = _getValues(totalAmount);
        _reflections[from] = _reflections[from].sub(reflectionAmount);
        _balances[to] = _balances[to].add(totalTransferAmount);
        _reflections[to] = _reflections[to].add(reflectedTransferAmount);
        _takeLiquidity(takeLiquidity);
        _reflectFee(reflectionFee, taxedFee);
        emit Transfer(from, to, totalTransferAmount);
    }

    function _transferFromExcluded(address from, address to, uint256 totalAmount) private {
        (uint256 reflectionAmount, uint256 reflectedTransferAmount, uint256 reflectionFee, uint256 totalTransferAmount, uint256 taxedFee, uint256 takeLiquidity) = _getValues(totalAmount);
        _balances[from] = _balances[from].sub(totalAmount);
        _reflections[from] = _reflections[from].sub(reflectionAmount);
        _reflections[to] = _reflections[to].add(reflectedTransferAmount);   
        _takeLiquidity(takeLiquidity);
        _reflectFee(reflectionFee, taxedFee);
        emit Transfer(from, to, totalTransferAmount);
    }

    function setRouterAddress(address newRouter) public onlyOwner() {
        IDexRouter02 _newRouter = IDexRouter02(newRouter);
        dexPair = IDexFactory(_newRouter.factory()).createPair(address(this), _newRouter.WETH());
        dexRouter = _newRouter;
    }

    function getNativeCurrencyQuantity() public view returns (uint256) {
        return address(this).balance;        
    }  

    function getNativeCurrency() external onlyOwner() {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function rescueTokens(address _tokenContract, uint256 _amount) external onlyOwner {
        IToken tokenContract = IToken(_tokenContract);
        tokenContract.transfer(msg.sender, _amount);
    }
}