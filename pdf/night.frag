#version 440
// Ночной режим страницы: яркость наоборот, оттенок сохраняется (Y' = 1 − Y в YUV, BT.601) —
// белая бумага становится тёмно-серой, чёрный текст светлым, цветные картинки остаются узнаваемыми.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;

void main()
{
    vec4 c = texture(source, qt_TexCoord0);
    float y = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    float u = dot(c.rgb, vec3(-0.14713, -0.28886, 0.436));
    float v = dot(c.rgb, vec3(0.615, -0.51499, -0.10001));
    y = mix(0.07, 0.88, 1.0 - y);   // не чистый чёрный и не чистый белый — мягче для глаз
    vec3 rgb = vec3(y + 1.13983 * v, y - 0.39465 * u - 0.58060 * v, y + 2.03211 * u);
    fragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * c.a * qt_Opacity;
}
