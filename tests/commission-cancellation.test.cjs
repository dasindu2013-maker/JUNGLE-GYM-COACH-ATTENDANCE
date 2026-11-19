const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(require('node:path').join(__dirname, '../index.html'), 'utf8');
const handler = html.slice(html.indexOf('    const commissionCancellationsInProgress'), html.indexOf('    window.reassignMembershipCommission'));
const filters = html.slice(html.indexOf('    function payrollCommissionName'), html.indexOf('    function calculateCoachPayroll'));

function fixture() {
  const record = {id: 42, receipt_number: '10117', source_key: 'sheet:271:commission', staff_name: 'Chaminda', member_name: 'Kalindu', commission_amount: 2600, payment_date: '2026-11-11'};
  const calls = [], messages = [], reason = {value: 'Duplicate registration'}, button = {disabled: false};
  const context = {
    window: {confirm: () => true}, currentProfile: {role: 'admin'}, adminMembershipCommissions: [record],
    document: {getElementById: id => id.startsWith('commission-reason-') ? reason : id.startsWith('cancel-commission-') ? button : {}},
    clearMessage() {}, showMessage: (_, text, type) => messages.push({text, type}), money: n => String(n),
    renderPayrollSummary() {}, renderMembershipCommissionCorrections() {},
    db: {rpc: async (name, args) => {calls.push({name, args}); return {error: null};},
      from: () => ({select: () => ({order: async () => ({data: [record], error: null})})})}
  };
  vm.createContext(context); vm.runInContext(filters + handler, context);
  return {context, calls, messages, reason, button, record, cancel: () => context.window.cancelMembershipCommission('42')};
}

(async () => {
  let f = fixture(); await f.cancel();
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].name, 'admin_cancel_membership_commission');
  assert.equal(f.calls[0].args.p_expected_receipt, '10117');
  assert.equal(f.calls[0].args.p_expected_source_key, 'sheet:271:commission');
  assert.equal(f.calls[0].args.p_expected_commission, 2600);
  assert.equal(f.record.commission_amount, 0); assert.equal(f.record.commission_before_cancellation, 2600);
  assert.equal(f.context.monthlyCommissionForCoach({full_name:'Chaminda'}, '2026-11'), 0);
  assert.equal(f.button.disabled, false);
  await f.cancel(); assert.equal(f.calls.length, 1);

  f = fixture(); f.context.currentProfile.role = 'coach'; await f.cancel(); assert.equal(f.calls.length, 0);
  f = fixture(); f.reason.value = 'bad'; await f.cancel(); assert.equal(f.calls.length, 0);
  f = fixture(); f.context.window.confirm = () => false; await f.cancel(); assert.equal(f.calls.length, 0);
  f = fixture(); f.context.db.rpc = async () => ({error: {message: 'Commission changed'}});
  await f.cancel(); assert.equal(f.record.commission_amount, 2600); assert.equal(f.messages.at(-1).type, 'error');
  f = fixture(); f.context.db.from = () => ({select: () => ({order: async () => ({error: {message:'Offline'}})})});
  await f.cancel(); assert.equal(f.record.commission_amount, 0); assert.match(f.messages.at(-1).text, /Cancellation saved/);
  f = fixture(); let release;
  f.context.db.rpc = (name,args) => {f.calls.push({name,args}); return new Promise(resolve => {release = resolve;});};
  const first = f.cancel(); await f.cancel(); assert.equal(f.calls.length, 1); release({error:null}); await first;
  console.log('PASS: exact receipt/source snapshot, payroll exclusion, audit amount, admin/reason checks, confirmation, retry protection, RPC failure and refresh failure');
})().catch(error => {console.error(error); process.exitCode = 1;});
