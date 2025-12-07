## Instruccions per accedir
1. Descarregar zip
2. Entrar en el laboratori de aws
3. Anar a CloudFormation i crear un stack (with new resources)
4. A 'Specify template', selecciona 'Upload template file'
5. Selecciona el fitxer 'ldap-stack.yaml'
6. Fer clic a 'Next'.
7. Nombra el stack i escollaix una 'key' (Assumeix que tens una)
8. La resta del stack amb les opcions 'default' i crea el stack
9. Espera a que finalitzi la creació.
10. Al acabar, ves a 'Outputs' y fes clic a 'LAMURL'
11. Esperar a que el server acabi de crearse (Pot tardar un bon rato)

## Extres

Si utilitzes la comanda 'sudo cat /var/log/user-data.log' en una de les instancies, podrás veure en quin punt de la creació está.
