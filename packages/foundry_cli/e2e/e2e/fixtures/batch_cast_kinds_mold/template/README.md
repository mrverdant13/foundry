# {{ project_name }}

use_null_safety={{ use_null_safety }}
port={{ port }}
scale={{ scale }}
project_type={{ project_type }}
platforms={% for p in platforms %}{{ p }}{% unless forloop.last %},{% endunless %}{% endfor %}
