'use strict';

const fs = require('fs');
const path = require('path');

const repositoryRoot = path.resolve(__dirname, '..');
const sourcePath = path.join(repositoryRoot,
	'luci-proto-amneziawg3/htdocs/luci-static/resources/protocol/amneziawg3.js');
const ucodePath = path.join(repositoryRoot,
	'luci-proto-amneziawg3/root/usr/share/rpcd/ucode/luci.amneziawg3');
const source = fs.readFileSync(sourcePath, 'utf8');
const ucode = fs.readFileSync(ucodePath, 'utf8');

if (!String.prototype.format) {
	Object.defineProperty(String.prototype, 'format', {
		value: function(...args) {
			let index = 0;
			return this.replace(/%[sd]/g, () => String(args[index++]));
		},
		configurable: true
	});
}

const rpcCalls = [];
const rpc = {
	declare(spec) {
		return function(...args) {
			rpcCalls.push({ method: spec.method, args });
			if (spec.method === 'deriveStoredPublicKey')
				return Promise.resolve({ pub: 'PUBLIC' });
			return Promise.resolve(spec.method === 'generatePresharedKey'
				? 'PSK' : { priv: 'PRIVATE', pub: 'PUBLIC' });
		};
	}
};

const extend = value => value;
const form = {
	Value: function Value() {},
	DynamicList: function DynamicList() {},
	Flag: function Flag() {},
	SectionValue: function SectionValue() {},
	GridSection: function GridSection() {},
	DummyValue: { extend }
};
const ui = { createHandlerFn: () => function() {} };
const savedUci = { private_key: 'SAVED' };
const uci = {
	get(config, section, option) {
		return config === 'network' && section === 'awg3'
			? savedUci[option] : undefined;
	}
};
const network = {
	registerProtocol(name, protocol) {
		if (name !== 'amneziawg3')
			throw new Error(`Unexpected protocol ${name}`);
		return protocol;
	},
	getIfnameOf(value) { return value; }
};
const translate = value => value;
const element = () => ({});

const loadModule = new Function('ui', 'uci', 'rpc', 'form', 'network', '_', 'E', source);
const protocol = loadModule(ui, uci, rpc, form, network, translate, element);
const options = {};
const values = {};
const subsection = {
	option() { return {}; }
};
const section = {
	section: 'awg3',
	tab() {},
	formvalue(sectionId, name) {
		return values[name];
	},
	taboption(tab, type, name) {
		if (name === '_peers') {
			return {
				depends() {},
				subsection
			};
		}
		const option = {};
		options[name] = option;
		return option;
	}
};

protocol.renderFormOptions(section);

function validateTuple(jc, jmin, jmax) {
	values.jc = jc;
	values.jmin = jmin;
	values.jmax = jmax;
	return options.jc.validate('awg3', jc);
}

function expectValid(jc, jmin, jmax) {
	const result = validateTuple(jc, jmin, jmax);
	if (result !== true)
		throw new Error(`Expected (${jc}, ${jmin}, ${jmax}) to be valid: ${result}`);
}

function expectInvalid(jc, jmin, jmax) {
	const result = validateTuple(jc, jmin, jmax);
	if (result === true)
		throw new Error(`Expected (${jc}, ${jmin}, ${jmax}) to be rejected`);
}

expectValid('', '', '');
expectValid('1', '0', '1');
expectValid('128', '1279', '1280');
expectInvalid('', '10', '');
expectInvalid('', '', '50');
expectInvalid('4', '70', '40');
expectInvalid('4', '40', '40');
expectInvalid('0', '0', '1');
expectInvalid('129', '0', '1');
expectInvalid('1', '1280', '1280');
expectInvalid('1', '0', '1281');
expectInvalid('65535', '0', '1');
expectInvalid('1', '65535', '65535');
expectInvalid('1', '0', '65535');
expectInvalid('nope', '0', '1');
expectInvalid('1', '-1', '2');
expectInvalid('1', '0', '01');

if (!source.includes('values.jc * values.jmax > 163840'))
	throw new Error('LuCI allocation budget validation is missing');
if (/params:\s*\[\s*['"]private_key['"]\s*\]/.test(source))
	throw new Error('LuCI RPC must not send a private key as a parameter');
if (!ucode.includes("command([ 'derive-stored-public-key', section ])"))
	throw new Error('ucode must pass only the validated section to the command wrapper');
if (!ucode.includes("system(argv)") || !ucode.includes('const handles = pipe()'))
	throw new Error('ucode must use direct argv execution with an anonymous output pipe');
if (/\bpopen\s*\(|\/bin\/sh|\bsh\s+-c\b|shellquote/.test(ucode))
	throw new Error('ucode key RPC must not invoke a shell');

values.private_key = 'CHANGED';
rpcCalls.length = 0;
if (options.public_key.load('awg3') !== '')
	throw new Error('Unsaved private key must leave the derived public key blank');
if (rpcCalls.length !== 0)
	throw new Error('Unsaved private key must not be sent to any RPC method');

values.private_key = 'SAVED';
rpcCalls.length = 0;
options.public_key.load('awg3').then(result => {
	if (result !== 'PUBLIC')
		throw new Error('Stored public key derivation returned an unexpected value');
	if (rpcCalls.length !== 1 ||
	    rpcCalls[0].method !== 'deriveStoredPublicKey' ||
	    rpcCalls[0].args.length !== 1 || rpcCalls[0].args[0] !== 'awg3')
		throw new Error('Stored public key RPC must receive only the UCI section name');
	console.log('LuCI JavaScript validation tests passed.');
}).catch(error => {
	console.error(error);
	process.exitCode = 1;
});
