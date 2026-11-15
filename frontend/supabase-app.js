/* Browser frontend connection. This contains only the Supabase publishable key.
 * Authorization and row ownership are enforced by PostgreSQL RLS, not this code.
 */
(() => {
  'use strict';

  const SUPABASE_URL = 'https://ovijbsmxpkpwztfnkiga.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_mMeqGX0mGvDi9T9VpDxuvQ_vfTB2xdQ';
  const ROLE_NAMES = {
    md: 'MD / Board', gfm: 'Group Finance Manager', trc: 'Treasury Controller',
    rgm: 'Regional Gas Manager', ymm: 'Yas/Mixx Manager', wdm: 'Wakala Development Manager',
    ia: 'Internal Auditor', acc: 'Accountant', hr: 'HR Manager', po: 'Procurement Officer',
    rsp: 'Route Sales Person', ssp: 'Shop Sales Person'
  };

  const $ = (selector) => document.querySelector(selector);
  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  let currentUser = null;
  let memberships = [];
  let currentOrg = null;

  const setMessage = (text, error = false) => {
    const node = $('#app-message');
    node.textContent = text;
    node.classList.toggle('error', error);
  };

  const showSession = (session) => {
    currentUser = session?.user || null;
    $('#login-card').classList.toggle('hidden', Boolean(currentUser));
    $('#app').classList.toggle('hidden', !currentUser);
    if (!currentUser) {
      memberships = [];
      currentOrg = null;
      return;
    }
    $('#signed-in-as').textContent = currentUser.email || 'Signed in';
    void loadMemberships();
  };

  async function loadMemberships() {
    setMessage('Checking your organization membership…');
    const { data, error } = await client
      .from('memberships')
      .select('organization_id, role, active')
      .eq('user_id', currentUser.id)
      .eq('active', true);

    if (error) {
      setMessage(`Could not load membership: ${error.message}`, true);
      return;
    }
    memberships = data || [];
    if (!memberships.length) {
      setMessage('You are signed in, but no active organization membership was found. Ask an organization administrator to provision your membership.', true);
      $('#role-label').textContent = '';
      $('#organization').replaceChildren();
      $('#sales-entry').classList.add('hidden');
      $('#sales-rows').replaceChildren();
      return;
    }

    const select = $('#organization');
    select.replaceChildren(...memberships.map((membership, index) => {
      const option = document.createElement('option');
      option.value = String(index);
      option.textContent = `${membership.organization_id} — ${ROLE_NAMES[membership.role] || membership.role}`;
      return option;
    }));
    const match = memberships.findIndex((membership) => membership.organization_id === currentOrg);
    select.value = String(match >= 0 ? match : 0);
    await selectOrganization();
  }

  async function selectOrganization() {
    const membership = memberships[Number($('#organization').value)];
    if (!membership || !currentUser) return;
    currentOrg = membership.organization_id;
    $('#role-label').textContent = `Role: ${ROLE_NAMES[membership.role] || membership.role}`;
    const canRecord = ['rsp', 'ssp'].includes(membership.role);
    $('#sales-entry').classList.toggle('hidden', !canRecord);
    await loadSales();
  }

  async function loadSales() {
    if (!currentOrg) return;
    setMessage('Loading records (Supabase RLS limits which rows you can see)…');
    const { data, error } = await client
      .from('sales_records')
      .select('sale_id, salesperson_user_id, payload, created_at')
      .eq('organization_id', currentOrg)
      .order('created_at', { ascending: false })
      .limit(200);

    if (error) {
      setMessage(`Could not load sales. Check that both SQL migrations were applied and the account has an active membership: ${error.message}`, true);
      return;
    }

    const tbody = $('#sales-rows');
    tbody.replaceChildren();
    for (const row of data || []) {
      const payload = row.payload || {};
      const tr = document.createElement('tr');
      const values = [payload.date || '', payload.product || '', payload.quantity ?? '',
        payload.unit_price == null ? '' : Number(payload.unit_price).toLocaleString(),
        payload.total == null ? '' : Number(payload.total).toLocaleString()];
      for (const value of values) {
        const td = document.createElement('td');
        td.textContent = String(value);
        tr.append(td);
      }
      tbody.append(tr);
    }
    setMessage(`${(data || []).length} cloud record(s) loaded. Access is filtered by database policies.`);
  }

  $('#login-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = $('#login-button');
    button.disabled = true;
    const message = $('#login-message');
    message.classList.remove('hidden', 'error');
    message.textContent = 'Sending sign-in link…';
    const { error } = await client.auth.signInWithOtp({
      email: $('#email').value.trim(),
      options: {
        shouldCreateUser: false,
        emailRedirectTo: `${window.location.origin}${window.location.pathname}`
      }
    });
    button.disabled = false;
    message.classList.toggle('error', Boolean(error));
    message.textContent = error
      ? `Sign-in link could not be sent: ${error.message}`
      : 'Check your email for the sign-in link. If no email arrives, confirm the account exists and Supabase Auth email settings are configured.';
  });

  $('#organization').addEventListener('change', () => void selectOrganization());
  $('#reload').addEventListener('click', () => void loadSales());
  $('#signout').addEventListener('click', async () => {
    const { error } = await client.auth.signOut();
    if (error) setMessage(`Sign out failed: ${error.message}`, true);
  });

  $('#sale-date').value = new Date().toISOString().slice(0, 10);
  $('#sale-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const membership = memberships[Number($('#organization').value)];
    if (!currentUser || !currentOrg || !membership || !['rsp', 'ssp'].includes(membership.role)) {
      setMessage('Only an active, authenticated salesperson can submit their own sale from this form.', true);
      return;
    }

    const quantity = Number($('#quantity').value);
    const unitPrice = Number($('#unit-price').value);
    if (!(quantity > 0) || !(unitPrice >= 0) || !Number.isFinite(quantity * unitPrice)) {
      setMessage('Enter a valid positive quantity and non-negative unit price.', true);
      return;
    }

    const button = $('#save-sale');
    button.disabled = true;
    const { error } = await client.from('sales_records').insert({
      organization_id: currentOrg,
      sale_id: crypto.randomUUID(),
      salesperson_user_id: currentUser.id,
      payload: {
        date: $('#sale-date').value,
        product: $('#product').value.trim(),
        quantity,
        unit_price: unitPrice,
        total: Math.round(quantity * unitPrice * 100) / 100
      }
    });
    button.disabled = false;
    if (error) {
      setMessage(`Sale was not saved: ${error.message}`, true);
      return;
    }
    $('#sale-form').reset();
    $('#sale-date').value = new Date().toISOString().slice(0, 10);
    setMessage('Sale saved to the cloud.');
    await loadSales();
  });

  client.auth.onAuthStateChange((_event, session) => showSession(session));
  client.auth.getSession().then(({ data, error }) => {
    if (error) {
      $('#login-message').classList.remove('hidden');
      $('#login-message').classList.add('error');
      $('#login-message').textContent = `Could not restore sign-in: ${error.message}`;
    }
    showSession(data?.session || null);
  });
})();
