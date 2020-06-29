#
# Authoritive FFHO DNS Server configuration (dns01/dns02 anycast)
#

{% if salt['pillar.get']('netbox:role:name') %}
{%- set role = salt['pillar.get']('netbox:role:name') %}
{% else %}
{%- set role = salt['pillar.get']('netbox:device_role:name') %}
{% endif %}

# Get all nodes for DNS records
{% set nodes = salt['mine.get']('netbox:platform:slug:linux', 'minion_id', tgt_type='pillar') %}
{% set cnames = salt['pillar.get']('netbox:config_context:dns_zones:cnames') %}

{% if 'dnsserver' in role %}
include:
  - dns-server

python-dnspython:
  pkg.installed:
    - name: python-dnspython

# Bind options
/etc/bind/named.conf.options:
  file.managed:
    - source: salt://dns-server/auth/named.conf.options
    - require:
      - pkg: bind9
    - watch_in:
      - cmd: rndc-reload

# Configure authoritive zones in local config
/etc/bind/named.conf.local:
  file.managed:
    - source: salt://dns-server/auth/named.conf.local
    - template: jinja
    - require:
      - pkg: bind9
    - watch_in:
      - cmd: rndc-reload

/etc/bind/zones:
  file.directory:
    - user: bind
    - group: bind
    - mode: 775
    - require:
      - pkg: bind9

  

{% if not salt['file.file_exists' ]('/etc/bind/zones/db.in.ffmuc.net') %}
/etc/bind/zones/db.in.ffmuc.net:
  file.managed:
    - source: salt://dns-server/auth/db.in.ffmuc.net
    - user: bind
    - group: bind
    - mode: 775
    - require:
      - file: /etc/bind/zones
    - watch_in:
      - cmd: rndc-reload
{% endif %}

{% if not salt['file.file_exists' ]('/etc/bind/zones/db.ext.ffmuc.net') %}
/etc/bind/zones/db.ext.ffmuc.net:
  file.managed:
    - source: salt://dns-server/auth/db.ext.ffmuc.net
    - user: bind
    - group: bind
    - mode: 775
    - require:
      - file: /etc/bind/zones
    - watch_in:
      - cmd: rndc-reload
{% endif %}

{% if not salt['file.file_exists' ]('/etc/bind/zones/db.80.10.in-addr.arpa') %}
/etc/bind/zones/db.80.10.in-addr.arpa:
  file.managed:
    - source: salt://dns-server/auth/db.80.10.in-addr.arpa
    - user: bind
    - group: bind
    - mode: 775
    - require:
      - file: /etc/bind/zones
    - watch_in:
      - cmd: rndc-reload
{% endif %}

{% if not salt['file.file_exists' ]('/etc/bind/zones/db.1.0.a.0.8.0.6.0.1.0.0.2.ip6.arpa') %}
/etc/bind/zones/db.1.0.a.0.8.0.6.0.1.0.0.2.ip6.arpa:
  file.managed:
    - source: salt://dns-server/auth/db.1.0.a.0.8.0.6.0.1.0.0.2.ip6.arpa
    - user: bind
    - group: bind
    - mode: 775
    - require:
      - file: /etc/bind/zones
    - watch_in:
      - cmd: rndc-reload
{% endif %}


dns-key:
  file.managed:
    - name: /etc/bind/salt-master.key
    - source: salt://dns-server/auth/salt-master.key
    - template: jinja
    - user: bind
    - group: bind
    - mode: 600
    - require:
      - pkg: bind9


# Create DNS records for each node
{% for node_id in nodes %}
{%- set address = salt['mine.get'](node_id,'minion_address', tgt_type='glob')[node_id] %}
{%- set address6 = salt['mine.get'](node_id,'minion_address6', tgt_type='glob')[node_id] %}

{%- set external_address = salt['mine.get'](node_id,'minion_external_ip', tgt_type='glob') %}
{%- set external_address6 = salt['mine.get'](node_id,'minion_external_ip6', tgt_type='glob') %}

{% if 'mine_interval' not in address %}
record-A-{{ node_id }}:
  ddns.present:
    - name: {{ node_id }}.
    - zone: in.ffmuc.net
    - ttl: 60
    - data: {{ address | regex_replace('/\d+$','') }}
    - rdtype: A
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key

record-PTR-{{ node_id }}:
  ddns.present:
    - name: {{  salt.network.reverse_ip(address | regex_replace('/\d+$','')) }}.
    - zone: 80.10.in-addr.arpa
    - ttl: 60
    - data: {{ node_id }}.
    - rdtype: PTR
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key


{% endif %}

{% if 'mine_interval' not in address6 %}
record-AAAA-{{ node_id }}:
  ddns.present:
    - name: {{ node_id }}.
    - zone: in.ffmuc.net
    - ttl: 60
    - data: {{ address6 | regex_replace('/\d+$','') }}
    - rdtype: AAAA
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key

record-PTR6-{{ node_id }}:
  ddns.present:
    - name: {{  salt.network.reverse_ip(address6 | regex_replace('/\d+$','')) }}.
    - zone: 1.0.a.0.8.0.6.0.1.0.0.2.ip6.arpa
    - ttl: 60
    - data: {{ node_id }}.
    - rdtype: PTR
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key


{% endif %}

# Create Entries in ext.ffmuc.net for each device with external IPs
{% if external_address and external_address[node_id] | length > 0 and not '__data__' in external_address[node_id] %}
record-A-external-{{ node_id }}:
  ddns.present:
    {% set node = node_id | regex_search('(^\w+(\d+)?)') %}
    - name: {{ node[0] }}.ext.ffmuc.net.
    - zone: ext.ffmuc.net
    - ttl: 60
    - data: {{ external_address[node_id] | first }}
    - rdtype: A
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key
{% endif %}

{% if external_address6 and external_address[node_id] | length > 0 and not '__data__' in external_address6[node_id] %}

record-AAAA-external-{{ node_id }}:
  ddns.present:
    {% set node = node_id | regex_search('(^\w+(\d+)?)') %}
    - name: {{ node[0] }}.ext.ffmuc.net.
    - zone: ext.ffmuc.net
    - ttl: 60
    - data: {{ external_address6[node_id] | first }} 
    - rdtype: AAAA
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key

{% endif %}
{% endfor %}

# Create CNAMES as defined in netbox:config_context:dns_zones:cnames or netbox:services (cnames field needs to be set to true)
{% set services = salt['pillar.get']('netbox:services') %}
{% for service in services %}
{% if services[service]['custom_fields']['cname'] %}
{% if services[service]['virtual_machine'] %}
{% if services[service]['custom_fields']['public'] %}
{% set target = services[service]['virtual_machine']['name'] | regex_search('(^\w+(\d+)?)') %}
{% do cnames.update({service: target[0] ~ '.ext.ffmuc.net' }) %}
{% else %}
{% do cnames.update({service: services[service]['virtual_machine']['name'] }) %}
{% endif %}
{% else %}
{% if services[service]['custom_fields']['public'] %}
{% set target = services[service]['device']['name'] | regex_search('(^\w+(\d+)?)') %}
{% do cnames.update({service: target[0] ~ '.ext.ffmuc.net' }) %}
{% else %}
{% do cnames.update({service: services[service]['device']['name'] }) %}
{% endif %}
{% endif %}
{% endif %}
{% endfor %}
{% for cname in cnames %}
record-CNAME-{{ cname }}:
  ddns.present:
    - name: {{ cname }}.
    {% if 'ext.ffmuc.net' in cname  %}
    - zone: ext.ffmuc.net
    {% else %}
    - zone: in.ffmuc.net
    {% endif %}
    - ttl: 60
    - data: {{ cnames[cname] }}.
    - rdtype: CNAME
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key
{% endfor %}

# Create extra DNS entries for devices not in pillars
{%- set extra_dns_entries = salt['extra_dns_entries.get_extra_dns_entries'](salt['pillar.get']('netbox:config_context:dns_zones:netbox_token'), salt['pillar.get']('netbox:config_context:dns_zones:netbox_url')) %}
{% for dns_entry in extra_dns_entries %}
{% if extra_dns_entries[dns_entry]['address'] != '' %}
record-A-extra-{{ dns_entry }}:
  ddns.present:
    - name: {{ dns_entry }}.
    - zone: in.ffmuc.net
    - ttl: 60
    - data: {{ extra_dns_entries[dns_entry]['address'] }}
    - rdtype: A
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key

{% endif %}

{% if extra_dns_entries[dns_entry]['address6'] %}

record-AAAA-extra-{{ dns_entry }}:
  ddns.present:
    - name: {{ dns_entry }}.
    - zone: in.ffmuc.net
    - ttl: 60
    - data: {{ extra_dns_entries[dns_entry]['address6'] }}
    - rdtype: AAAA
    - nameserver: 127.0.0.1
    - keyfile: /etc/bind/salt-master.key
    - keyalgorithm: hmac-sha512
    - replace_on_change: True
    - require:
      - pkg: python-dnspython
      - file: dns-key
{% endif %}

{% endfor %}
{% endif %}

