Simple Configuration [Management] System
========================================

SCS is a rudimentary configuration management and automated build system implented
in bash.  I developed this for the purpose of managing a multitude of related linux
system builds with a consistent set of configuration files but varied configurations
based upon their deployed location and environment (production vs alpha vs test or
site A versus site B).  Often times the only difference between a configuration on
two systems is a single set of variables (such as an IP or credentials).

Yes, it would be far easier (but less fun) to use an established system such as Puppet,
Chef, CFEngine, Ansible, or others, but the advantage here was that I could throw
this together and guarantee it's effectivness and success in a matter of days, while I
could not guarantee the same result using another tool.  Like ansible this system
relies on ssh with root keys from one or more central management servers, which makes
it fully clientless and simple to deploy and utilize.

I have built in a very basic IP management tool which should be easily replaced with
another tool that has an API, as needed.

I fully expect to replace this wholesale with Ansible or Puppet at some point, but
for now it serves it's purpose quite well and due to the conventions I have used it has
been very simple to expand and extend.

This is a work in progress so use it at your own risk.  The help is very much
incomplete, but again it's currently a fun side project and doing its job.
