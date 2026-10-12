-- User setup summary of one environment, to compare DEV and SIT (run as postgres, database hansacore).
-- The last query prints a fingerprint of every user, home tenant and role: equal fingerprints mean
-- identical user setups. "signed_in" only counts users who already logged in and may differ.
\pset pager off
\pset footer off
SELECT t.name AS home_tenant, count(*) AS users
  FROM hansacore.obj_user u JOIN hansacore.obj_base b ON b.id = u.id JOIN hansacore.obj_base t ON t.id = b.obj_br_tenant_id
 GROUP BY 1 ORDER BY 1;
SELECT u.email, t.name AS home_tenant,
       (SELECT string_agg(k.key_val, ',' ORDER BY k.key_val) FROM hansacore.obj_extn_rel r
          JOIN hansacore.enum_obj_rel typ ON typ.id = r.obj_rel_id AND typ.sym_key = 'HAS_ROLE'
          JOIN hansacore.obj_extn_key k ON k.obj_id = r.obj_trg_id WHERE r.obj_id = u.id) AS roles,
       (SELECT string_agg(m.tenant_role || '@' || mt.name, ', ' ORDER BY m.tenant_role, mt.name)
          FROM hansacore.tenant_membership m JOIN hansacore.obj_base mt ON mt.id = m.tenant_id
         WHERE m.user_id = u.id AND m.tenant_role <> 'MEMBER') AS admin_rights
  FROM hansacore.obj_user u JOIN hansacore.obj_base b ON b.id = u.id JOIN hansacore.obj_base t ON t.id = b.obj_br_tenant_id
 WHERE u.email ILIKE '%hansacore.com'
    OR EXISTS (SELECT 1 FROM hansacore.tenant_membership m WHERE m.user_id = u.id AND m.tenant_role <> 'MEMBER')
 ORDER BY 2, 1;
SELECT t.name AS tenant, d.domain_name, d.status, d.is_primary
  FROM hansacore.tenant_domain d JOIN hansacore.obj_base t ON t.id = d.tenant_id ORDER BY 2;
SELECT t.name AS tenant, i.provider, i.external_tenant_id
  FROM hansacore.tenant_idp_binding i JOIN hansacore.obj_base t ON t.id = i.tenant_id;
SELECT md5(string_agg(lower(u.email) || '|' || t.name || '|' || coalesce(
         (SELECT string_agg(k.key_val, ',' ORDER BY k.key_val) FROM hansacore.obj_extn_rel r
            JOIN hansacore.enum_obj_rel typ ON typ.id = r.obj_rel_id AND typ.sym_key = 'HAS_ROLE'
            JOIN hansacore.obj_extn_key k ON k.obj_id = r.obj_trg_id WHERE r.obj_id = u.id), ''),
         ';' ORDER BY lower(u.email))) AS user_setup_fingerprint,
       count(*) AS users, count(u.keycloak_user_id) AS signed_in
  FROM hansacore.obj_user u JOIN hansacore.obj_base b ON b.id = u.id JOIN hansacore.obj_base t ON t.id = b.obj_br_tenant_id;
