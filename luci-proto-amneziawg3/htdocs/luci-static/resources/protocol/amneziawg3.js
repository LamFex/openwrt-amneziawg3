// Copyright 2026 AWG OpenWrt3 contributors
// Licensed under the Apache License 2.0.

'use strict';
'require ui';
'require uci';
'require rpc';
'require form';
'require network';

var generateKeyPair = rpc.declare({
	object: 'luci.amneziawg3',
	method: 'generateKeyPair',
	expect: { keys: {} }
});

var deriveStoredPublicKey = rpc.declare({
	object: 'luci.amneziawg3',
	method: 'deriveStoredPublicKey',
	params: [ 'section' ],
	expect: { keys: {} }
});

var generatePresharedKey = rpc.declare({
	object: 'luci.amneziawg3',
	method: 'generatePresharedKey',
	expect: { key: '' }
});

function validateBase64Key(sectionId, value) {
	if (!value)
		return true;

	if (!value.match(/^[A-Za-z0-9+/]{43}=$/))
		return _('Invalid Base64 key');

	return true;
}

function validateRange(maximum) {
	return function(sectionId, value) {
		var match, low, high;

		if (!value)
			return true;

		match = String(value).match(/^([0-9]+)(?:-([0-9]+))?$/);
		if (!match)
			return _('Use a number or an inclusive range such as 30-45');

		low = Number(match[1]);
		high = (match[2] != null) ? Number(match[2]) : low;
		if (!Number.isInteger(low) || !Number.isInteger(high) ||
		    low < 0 || high < low || high > maximum)
			return _('Range must be between 0 and %d').format(maximum);

		return true;
	};
}

function validateJunkParameter(formSection, fieldName) {
	return function(sectionId, value) {
		var fields = [ 'jc', 'jmin', 'jmax' ];
		var limits = { jc: 128, jmin: 1279, jmax: 1280 };
		var values = {};
		var present = 0;

		fields.forEach(function(name) {
			var fieldValue = (name === fieldName)
				? value : formSection.formvalue(sectionId, name);
			values[name] = (fieldValue == null) ? '' : String(fieldValue);
			if (values[name] !== '')
				present++;
		});

		if (present === 0)
			return true;
		if (present !== 3)
			return _('Jc, Jmin, and Jmax must be either all present or all absent');

		for (var i = 0; i < fields.length; i++) {
			var name = fields[i];
			if (!/^(0|[1-9][0-9]*)$/.test(values[name]))
				return _('%s must be a canonical decimal integer').format(name.toUpperCase());
			values[name] = Number(values[name]);
			if (!Number.isSafeInteger(values[name]) || values[name] > limits[name])
				return _('%s exceeds the supported maximum of %d')
					.format(name.toUpperCase(), limits[name]);
		}

		if (values.jc < 1)
			return _('Jc must be between 1 and 128');
		if (values.jmax < 1)
			return _('Jmax must be between 1 and 1280');
		if (values.jmin >= values.jmax)
			return _('Jmin must be strictly less than Jmax');
		if (values.jc * values.jmax > 163840)
			return _('Jc multiplied by Jmax exceeds the 163840-byte allocation budget');

		return true;
	};
}

var keyPairButton = form.DummyValue.extend({
	cfgvalue(sectionId) {
		return E('button', {
			'class': 'btn cbi-button-action',
			'click': ui.createHandlerFn(this, function(sectionId) {
				var privateElement = this.section.getUIElement(sectionId, 'private_key'),
				    publicElement = this.section.getUIElement(sectionId, 'public_key');

				return generateKeyPair().then(function(keys) {
					if (!keys.priv || !keys.pub)
						throw new Error(_('Key generation failed'));
					privateElement.setValue(keys.priv);
					publicElement.setValue(keys.pub);
				});
			}, sectionId)
		}, [ _('Generate key pair') ]);
	}
});

var presharedKeyButton = form.DummyValue.extend({
	cfgvalue(sectionId) {
		return E('button', {
			'class': 'btn cbi-button-action',
			'click': ui.createHandlerFn(this, function(sectionId) {
				var keyElement = this.section.getUIElement(sectionId, 'preshared_key');

				return generatePresharedKey().then(function(key) {
					if (!key)
						throw new Error(_('Preshared key generation failed'));
					keyElement.setValue(key);
				});
			}, sectionId)
		}, [ _('Generate preshared key') ]);
	}
});

return network.registerProtocol('amneziawg3', {
	getI18n() {
		return _('AmneziaWG 3.1');
	},

	getIfname() {
		return this._ubus('l3_device') || this.sid;
	},

	getPackageName() {
		return 'amneziawg3';
	},

	isFloating() {
		return true;
	},

	isVirtual() {
		return true;
	},

	getDevices() {
		return null;
	},

	containsDevice(ifname) {
		return network.getIfnameOf(ifname) === this.getIfname();
	},

	renderFormOptions(s) {
		var o, peers, subsection;
		var u16Range = validateRange(65535);
		var u32Range = validateRange(4294967295);

		o = s.taboption('general', form.Value, 'private_key',
			_('Private key'),
			_('Required. The key remains in UCI and is never written to a temporary profile.'));
		o.password = true;
		o.rmempty = false;
		o.validate = validateBase64Key;

		o = s.taboption('general', form.Value, 'public_key',
			_('Public key'),
			_('Derived from the last saved private key and safe to share with the server administrator.'));
		o.write = function() {};
		o.load = function(sectionId) {
			var savedPrivateKey = uci.get('network', sectionId, 'private_key');
			var formPrivateKey = s.formvalue(sectionId, 'private_key');

			if (!savedPrivateKey || savedPrivateKey === 'generate' ||
			    (formPrivateKey && formPrivateKey !== savedPrivateKey))
				return '';

			return deriveStoredPublicKey(sectionId).then(function(keys) {
				return keys.pub || '';
			});
		};

		s.taboption('general', keyPairButton, '_generate_key_pair', ' ');

		o = s.taboption('general', form.Value, 'listen_port',
			_('Listen port'),
			_('Optional local UDP port. Leave empty to choose one automatically.'));
		o.datatype = 'port';
		o.placeholder = _('automatic');
		o.optional = true;

		o = s.taboption('general', form.DynamicList, 'addresses',
			_('IP addresses'),
			_('One or more addresses assigned to the tunnel interface.'));
		o.datatype = 'ipaddr';
		o.rmempty = false;

		o = s.taboption('general', form.Flag, 'nohostroute',
			_('Do not create endpoint host routes'),
			_('Enable only when endpoint reachability is managed by another route.'));
		o.default = o.disabled;

		o = s.taboption('advanced', form.Value, 'mtu',
			_('MTU'),
			_('Maximum transmission unit of the tunnel interface.'));
		o.datatype = 'range(576,8940)';
		o.placeholder = '1420';
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'fwmark',
			_('Firewall mark'),
			_('Optional 32-bit hexadecimal mark, for example 0xca6c.'));
		o.optional = true;
		o.validate = function(sectionId, value) {
			return !value || /^0x[0-9a-fA-F]{1,8}$/.test(value)
				? true : _('Invalid hexadecimal firewall mark');
		};

		o = s.taboption('advanced', form.DynamicList, 'ip6prefix',
			_('IPv6 routed prefix'));
		o.datatype = 'cidr6';
		o.optional = true;

		s.tab('awg3', _('AWG 3.1 parameters'),
			_('Copy these values exactly from the matching AmneziaWG 3.1 client profile. Jc is limited to 128, Jmax to 1280, and Jmin must be smaller than Jmax.'));

		[
			[ 'jc', _('Junk packet count') ],
			[ 'jmin', _('Minimum junk packet size') ],
			[ 'jmax', _('Maximum junk packet size') ]
		].forEach(function(spec) {
			o = s.taboption('awg3', form.Value, spec[0], spec[1]);
			o.validate = validateJunkParameter(s, spec[0]);
			o.optional = true;
		});

		[ 's1', 's2', 's3', 's4' ].forEach(function(name) {
			o = s.taboption('awg3', form.Value, name,
				name.toUpperCase() + ' ' + _('packet padding'));
			o.datatype = 'range(0,65535)';
			o.optional = true;
		});

		[ 'h1', 'h2', 'h3', 'h4' ].forEach(function(name) {
			o = s.taboption('awg3', form.Value, name,
				name.toUpperCase() + ' ' + _('message header'));
			o.validate = u32Range;
			o.placeholder = '1000000-2000000';
			o.optional = true;
		});

		[ 'i1', 'i2', 'i3', 'i4', 'i5' ].forEach(function(name) {
			o = s.taboption('awg3', form.Value, name,
				name.toUpperCase() + ' ' + _('special handshake value'));
			o.optional = true;
		});

		o = s.taboption('awg3', form.Value, 'header_protection_key',
			_('Header protection key'),
			_('When set, S1 through S4 must each be at least 12.'));
		o.password = true;
		o.optional = true;
		o.validate = function(sectionId, value) {
			var result = validateBase64Key(sectionId, value);
			if (result !== true || !value)
				return result;

			for (var i = 1; i <= 4; i++) {
				var padding = Number(s.formvalue(sectionId, 's' + i));
				if (!Number.isFinite(padding) || padding < 12)
					return _('S1 through S4 must each be at least 12 when header protection is enabled');
			}
			return true;
		};

		[
			[ 'content_padding_addition', _('Content padding addition') ],
			[ 'rekey_after_time', _('Rekey after time') ],
			[ 'rekey_timeout', _('Rekey timeout') ],
			[ 'reject_after_time', _('Reject after time') ],
			[ 'keepalive_timeout', _('Keepalive timeout') ],
			[ 'max_handshake_attempts', _('Maximum handshake attempts') ]
		].forEach(function(spec) {
			o = s.taboption('awg3', form.Value, spec[0], spec[1],
				_('Use one value or an inclusive range.'));
			o.validate = u16Range;
			o.optional = true;
		});

		o = s.taboption('awg3', form.Flag, 'random_trailers',
			_('Random trailers'));
		o.default = o.disabled;
		o.rmempty = true;

		o = s.taboption('awg3', form.Flag, 'disable_cookies',
			_('Disable cookies'));
		o.default = o.disabled;
		o.rmempty = true;

		s.tab('peers', _('Peers'),
			_('Each peer must use parameters compatible with this AWG 3.1 interface.'));

		peers = s.taboption('peers', form.SectionValue, '_peers',
			form.GridSection, 'amneziawg3_%s'.format(s.section));
		peers.depends('proto', 'amneziawg3');
		subsection = peers.subsection;
		subsection.anonymous = true;
		subsection.addremove = true;
		subsection.sortable = true;
		subsection.nodescriptions = true;
		subsection.addbtntitle = _('Add peer');
		subsection.modaltitle = _('Edit AmneziaWG 3.1 peer');

		o = subsection.option(form.Value, 'description', _('Description'));
		o.optional = true;

		o = subsection.option(form.Flag, 'disabled', _('Disabled'));
		o.default = o.disabled;
		o.editable = true;

		o = subsection.option(form.Value, 'public_key', _('Public key'));
		o.validate = validateBase64Key;
		o.rmempty = false;

		o = subsection.option(form.Value, 'preshared_key', _('Preshared key'));
		o.password = true;
		o.validate = validateBase64Key;
		o.optional = true;

		subsection.option(presharedKeyButton, '_generate_preshared_key', ' ');

		o = subsection.option(form.Value, 'endpoint_host', _('Endpoint host'));
		o.datatype = 'host';
		o.optional = true;

		o = subsection.option(form.Value, 'endpoint_port', _('Endpoint port'));
		o.datatype = 'port';
		o.placeholder = '51820';
		o.optional = true;

		o = subsection.option(form.DynamicList, 'allowed_ips', _('Allowed IPs'));
		o.datatype = 'ipaddr';
		o.rmempty = false;

		o = subsection.option(form.Flag, 'route_allowed_ips',
			_('Route allowed IPs'),
			_('Disabled by default to prevent an imported profile from replacing the current internet route.'));
		o.default = o.disabled;

		o = subsection.option(form.Value, 'persistent_keepalive',
			_('Persistent keepalive'),
			_('Seconds, or an inclusive range for AWG 3.1.'));
		o.validate = u16Range;
		o.optional = true;
	}
});
